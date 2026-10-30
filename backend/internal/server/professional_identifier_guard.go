package server

import (
	"errors"
	"net/http"

	"github.com/jackc/pgx/v5/pgconn"

	"malva/backend/internal/store"
)

const professionalIdentifierTakenCode = "str_sip_sudah_terdaftar"

func (s *Server) rejectTakenProfessionalIdentifier(r *http.Request, strNumber, sipNumber, excludeUserID string) error {
	for _, v := range []struct{ kind, number string }{{"str", strNumber}, {"sip", sipNumber}} {
		taken, err := s.store.ProfessionalIdentifierTaken(r.Context(), v.kind, v.number, excludeUserID)
		if err != nil {
			return err
		}
		if taken {
			return store.ErrProfessionalIdentifierTaken
		}
	}
	return nil
}

func writeProfessionalError(w http.ResponseWriter, err error) {
	var pgErr *pgconn.PgError
	identifierConflict := errors.Is(err, store.ErrProfessionalIdentifierTaken) ||
		(errors.As(err, &pgErr) && pgErr.Code == "23505" &&
			(pgErr.ConstraintName == "professional_credentials_str_uidx" || pgErr.ConstraintName == "professional_credentials_sip_uidx"))
	if identifierConflict {
		writeJSON(w, http.StatusConflict, map[string]string{
			"error": "Nomor STR atau SIP ini sudah terdaftar pada akun profesional lain. " +
				"Satu STR/SIP hanya boleh terhubung ke satu akun. Gunakan nomor lain " +
				"yang sah, atau masuk ke akun lama lalu hubungkan Gmail di menu Akun Google.",
			"code": professionalIdentifierTakenCode,
		})
		return
	}
	if store.IsUniqueViolation(err) {
		writeError(w, http.StatusConflict, errors.New("email or professional ID is already registered"))
		return
	}
	if errors.Is(err, store.ErrEmailOwnedByOther) {
		writeError(w, http.StatusConflict, errors.New("email is already registered to another account"))
		return
	}
	writeError(w, http.StatusInternalServerError, errors.New("could not save professional account"))
}
