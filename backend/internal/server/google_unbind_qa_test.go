package server

import (
	"context"
	"testing"

	"malva/backend/internal/store"
)

// QA regression (Edward) — mendokumentasikan perilaku email saat unbind untuk
// profesional yang MENDAFTAR MANDIRI dengan email ASLI (bukan placeholder),
// lalu menautkan Gmail yang SAMA dengan email akunnya.
//
// Ekspektasi produk: setelah Gmail dilepas, email ASLI akun TIDAK boleh
// diubah menjadi placeholder. Placeholder hanya dipulihkan untuk akun yang
// email-nya MEMANG placeholder sebelum bind (di-upgrade ke Gmail saat bind).
//
// Jalur nyata: `POST /v1/auth/register` memakai req.Email apa adanya
// (server.go register -> CreateUserParams{Email: req.Email}); profesional yang
// mendaftar dengan alamat Gmail lalu menautkan Gmail yang sama akan memenuhi
// syarat `EqualFold(accountEmail, ssoEmail)`, padahal email itu ASLI.
func TestUnbindGoogleKeepsRealEmailForSelfRegisteredProfessional(t *testing.T) {
	db, st := openOnboardingTestStore(t)
	ctx := context.Background()
	u := createIdentityTestUser(t, db, st, "professional", &store.ProfessionalCredential{Specialization: "Sp.KJ"})

	// Simulasikan pendaftaran mandiri dengan email ASLI (bukan placeholder).
	realEmail := "dr-asli-" + u.ID + "@gmail.com"
	if _, err := db.Exec(`UPDATE users SET email=$2 WHERE id=$1`, u.ID, realEmail); err != nil {
		t.Fatal(err)
	}
	// Tautkan Gmail yang SAMA dengan email akun.
	if _, err := st.LinkGoogleIdentity(ctx, u.ID, "sub-"+u.ID, realEmail, false); err != nil {
		t.Fatal(err)
	}
	// Bind tidak boleh mengubah email asli (bukan placeholder).
	if bound, err := st.GetUserByID(ctx, u.ID); err != nil || bound.Email != realEmail {
		t.Fatalf("prasyarat: bind mengubah email asli? got %q want %q (%v)", bound.Email, realEmail, err)
	}

	srv := newOnboardingTestServer(db)
	rec := callUnbind(srv, u.ID, "professional", `{"new_password":"NewPassword123!"}`)
	if rec.Code != 200 {
		t.Fatalf("expected 200, got %d %s", rec.Code, rec.Body.String())
	}

	finalUser, err := st.GetUserByID(ctx, u.ID)
	if err != nil {
		t.Fatal(err)
	}
	if finalUser.Email != realEmail {
		t.Fatalf("email ASLI dirusak saat unbind: got %q want %q "+
			"(email asli profesional diganti placeholder)", finalUser.Email, realEmail)
	}
}

// QA smoke scenario 10 — setelah pasien melepas Gmail, Gmail itu HARUS benar-benar
// bebas dan bisa ditautkan pasien lain. Membuktikan sso_email/sso_id benar-benar
// dilepas (tidak "terkunci") dan checkEmailOwnership tidak lagi melihat pemilik lama.
func TestUnbindGoogleFreesGmailForAnotherPatient(t *testing.T) {
	db, st := openOnboardingTestStore(t)
	ctx := context.Background()

	shared := "shared-" + "gmail" + "@example.test"
	patientA := createIdentityTestUser(t, db, st, "patient", nil)
	patientB := createIdentityTestUser(t, db, st, "patient", nil)

	if _, err := st.LinkGoogleIdentity(ctx, patientA.ID, "sub-a-"+patientA.ID, shared, false); err != nil {
		t.Fatalf("pasien A bind: %v", err)
	}
	srv := newOnboardingTestServer(db)
	rec := callUnbind(srv, patientA.ID, "patient", `{"new_password":"NewPassword123!"}`)
	if rec.Code != 200 {
		t.Fatalf("pasien A unbind: expected 200, got %d %s", rec.Code, rec.Body.String())
	}

	// Scenario 5 — unbind KEDUA kali harus 409 google_belum_tertaut.
	rec2 := callUnbind(srv, patientA.ID, "patient", `{"new_password":"NewPassword123!"}`)
	if rec2.Code != 409 || unbindCode(rec2) != googleNotLinkedCode {
		t.Fatalf("unbind kedua: expected 409 %s, got %d %s", googleNotLinkedCode, rec2.Code, rec2.Body.String())
	}

	// Scenario 9 — pasien A bisa MENAUTKAN ULANG Gmail yang sama setelah unbind.
	if _, err := st.LinkGoogleIdentity(ctx, patientA.ID, "sub-a-"+patientA.ID, shared, false); err != nil {
		t.Fatalf("pasien A gagal bind ulang setelah unbind: %v", err)
	}
	if recA := callUnbind(srv, patientA.ID, "patient", `{"new_password":"NewPassword123!"}`); recA.Code != 200 {
		t.Fatalf("pasien A unbind ulang: expected 200, got %d %s", recA.Code, recA.Body.String())
	}

	// Scenario 10 — pasien B harus bisa menautkan Gmail yang sama setelah A melepasnya.
	identB, err := st.LinkGoogleIdentity(ctx, patientB.ID, "sub-b-"+patientB.ID, shared, false)
	if err != nil {
		t.Fatalf("Gmail tidak bebas: pasien B gagal bind Gmail yang dilepas A: %v", err)
	}
	if !identB.Linked || identB.Email != shared {
		t.Fatalf("pasien B tidak tertaut ke Gmail yang dilepas: %+v", identB)
	}
}
