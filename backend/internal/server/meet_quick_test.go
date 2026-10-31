package server

import (
	"net/http"
	"net/http/httptest"
	"strings"
	"testing"

	"malva/backend/internal/auth"
)

// TestCreateQuickMeetRejectsEmptyMeetLink membuktikan endpoint /v1/meet/quick
// TIDAK membalas 201 dengan link kosong ketika Google membuat event tetapi
// tidak menyertakan entry point Meet.
//
// Sebelum diperbaiki, handler menyimpan apa adanya: klien menerima
// `meet_url: ""` lalu menampilkan tombol "Gabung" yang membuka URL kosong,
// sementara event tanpa ruang pertemuan tertinggal di kalender profesional.
// Perilaku sekarang disamakan dengan jalur sesi terjadwal
// (createScheduledMeet): event yatim dibatalkan dan klien menerima 502.
func TestCreateQuickMeetRejectsEmptyMeetLink(t *testing.T) {
	fake := &fakeMeetCalendar{createEventID: "evt-yatim", createMeetURL: "   "}
	srv := &Server{calendar: fake}

	rec := httptest.NewRecorder()
	req := httptest.NewRequest(http.MethodPost, "/v1/meet/quick", nil)
	srv.createQuickMeet(rec, req, auth.Claims{Subject: "prof-1", Role: "professional"})

	if rec.Code != http.StatusBadGateway {
		t.Fatalf("status = %d, mau %d (body: %s)", rec.Code, http.StatusBadGateway, rec.Body.String())
	}
	if strings.Contains(rec.Body.String(), `"meet_url"`) {
		t.Errorf("respons tidak boleh memuat meet_url kosong: %s", rec.Body.String())
	}
	if !strings.Contains(rec.Body.String(), "tidak mengembalikan link Meet") {
		t.Errorf("pesan harus menjelaskan kegagalan link Meet, dapat: %s", rec.Body.String())
	}
	if len(fake.cancelOnlyCalls) != 1 || fake.cancelOnlyCalls[0].eventID != "evt-yatim" {
		t.Errorf("event tanpa link harus dibatalkan agar tidak menggantung, dapat %+v", fake.cancelOnlyCalls)
	}
}

// TestCreateQuickMeetReturnsLink memastikan jalur sukses tetap membuat event
// atas nama profesional pemanggil dan mengembalikan link yang diterima.
func TestCreateQuickMeetReturnsLink(t *testing.T) {
	const wantURL = "https://meet.google.com/abc-defg-hij"
	fake := &fakeMeetCalendar{createEventID: "evt-1", createMeetURL: wantURL}
	srv := &Server{calendar: fake}

	rec := httptest.NewRecorder()
	req := httptest.NewRequest(http.MethodPost, "/v1/meet/quick", nil)
	srv.createQuickMeet(rec, req, auth.Claims{Subject: "prof-1", Role: "professional"})

	if rec.Code != http.StatusCreated {
		t.Fatalf("status = %d, mau %d (body: %s)", rec.Code, http.StatusCreated, rec.Body.String())
	}
	if !strings.Contains(rec.Body.String(), wantURL) {
		t.Errorf("respons harus memuat link Meet, dapat: %s", rec.Body.String())
	}
	if fake.createForUser != "prof-1" {
		t.Errorf("event dibuat untuk %q, mau %q", fake.createForUser, "prof-1")
	}
	if len(fake.cancelOnlyCalls) != 0 {
		t.Errorf("tidak diharapkan CancelMeetEvent pada jalur sukses, dapat %+v", fake.cancelOnlyCalls)
	}
}

// TestCreateQuickMeetRequiresProfessional memastikan pasien tidak bisa membuat
// link Meet lewat endpoint profesional ini.
func TestCreateQuickMeetRequiresProfessional(t *testing.T) {
	fake := &fakeMeetCalendar{createEventID: "evt-1", createMeetURL: "https://meet.google.com/x"}
	srv := &Server{calendar: fake}

	rec := httptest.NewRecorder()
	req := httptest.NewRequest(http.MethodPost, "/v1/meet/quick", nil)
	srv.createQuickMeet(rec, req, auth.Claims{Subject: "pasien-1", Role: "patient"})

	if rec.Code != http.StatusForbidden {
		t.Fatalf("status = %d, mau %d", rec.Code, http.StatusForbidden)
	}
	if fake.createCalls != 0 {
		t.Errorf("pasien tidak boleh memicu pembuatan event, dapat %d panggilan", fake.createCalls)
	}
}

// TestCreateQuickMeetWithoutCalendar memastikan server tanpa konfigurasi Google
// membalas 501 dengan pesan Indonesia, bukan 500 generik.
func TestCreateQuickMeetWithoutCalendar(t *testing.T) {
	srv := &Server{}

	rec := httptest.NewRecorder()
	req := httptest.NewRequest(http.MethodPost, "/v1/meet/quick", nil)
	srv.createQuickMeet(rec, req, auth.Claims{Subject: "prof-1", Role: "professional"})

	if rec.Code != http.StatusNotImplemented {
		t.Fatalf("status = %d, mau %d", rec.Code, http.StatusNotImplemented)
	}
}
