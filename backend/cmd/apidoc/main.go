// Command apidoc menghasilkan inventaris rute API dan skema OpenAPI untuk
// backend Malva langsung dari sumber kebenaran: fungsi Routes() di
// internal/server/server.go.
//
// Pemakaian (dijalankan dari folder backend/):
//
//	go run ./cmd/apidoc            # tulis docs/API_ROUTES.md + docs/openapi.yaml
//	go run ./cmd/apidoc -check     # verifikasi berkas di disk sudah sinkron (exit 1 bila beda)
//	go run ./cmd/apidoc -root ..   # tentukan root repo (default "..")
//
// Program ini hanya memakai standard library dan sengaja TIDAK menambah
// dependency apa pun ke modul backend.
package main

import (
	"bufio"
	"bytes"
	"flag"
	"fmt"
	"os"
	"path/filepath"
	"regexp"
	"strings"
)

// route merepresentasikan satu pendaftaran rute dari Routes().
type route struct {
	Method  string // GET, POST, PATCH, PUT, DELETE
	Path    string // contoh: /v1/auth/register
	Handler string // nama fungsi handler tanpa prefix "s."
	Wrapper string // ekspresi pembungkus lengkap, mis. s.requireAuth(s.register)
	Auth    string // hasil klasifikasi: bearer / bearer (admin) / publik / ...
	Line    int    // nomor baris di server.go
	Static  bool   // true untuk penyajian berkas statis (mux.Handle)
}

// handleFuncRe mencocokkan baris mux.HandleFunc("METHOD /path", <wrapper>).
// Kelompok 3 menangkap ekspresi pembungkus hingga kurung tutup pertama, yang
// cukup untuk mengenali pembungkus terluar (requireAuth/requireAdmin/public/
// rateLimit/paymentWebhook/realtimeWS) maupun handler telanjang (s.root).
var handleFuncRe = regexp.MustCompile(`mux\.HandleFunc\("([A-Z]+) (/[^"]*)", (s\.[^)]+)\)`)

// handleRe mencocokkan baris mux.Handle("METHOD /path", ...) untuk penyajian statis.
var handleRe = regexp.MustCompile(`mux\.Handle\("([A-Z]+) (/[^"]*)",`)

// pathParamRe mengekstrak parameter path seperti {user_id}.
var pathParamRe = regexp.MustCompile(`\{([^}]+)\}`)

func main() {
	root := flag.String("root", "..", "root repo (folder yang memuat backend/ dan docs/)")
	check := flag.Bool("check", false, "verifikasi berkas di disk sudah sinkron; exit 1 bila berbeda")
	flag.Parse()

	serverPath := filepath.Join(*root, "backend", "internal", "server", "server.go")
	routes, err := parseRoutes(serverPath)
	if err != nil {
		fmt.Fprintf(os.Stderr, "apidoc: gagal membaca %s: %v\n", serverPath, err)
		os.Exit(1)
	}

	markdown := renderMarkdown(routes)
	openapi := renderOpenAPI(routes)

	routesOut := filepath.Join(*root, "docs", "API_ROUTES.md")
	openapiOut := filepath.Join(*root, "docs", "openapi.yaml")

	apiCount := 0
	for _, r := range routes {
		if !r.Static {
			apiCount++
		}
	}

	if *check {
		if err := checkFile(routesOut, markdown); err != nil {
			fmt.Fprintf(os.Stderr, "apidoc -check GAGAL: %v\n", err)
			os.Exit(1)
		}
		if err := checkFile(openapiOut, openapi); err != nil {
			fmt.Fprintf(os.Stderr, "apidoc -check GAGAL: %v\n", err)
			os.Exit(1)
		}
		fmt.Printf("apidoc -check OK: %d endpoint API (+%d statis) sinkron di %s & %s\n",
			apiCount, len(routes)-apiCount, routesOut, openapiOut)
		return
	}

	if err := writeFile(routesOut, markdown); err != nil {
		fmt.Fprintf(os.Stderr, "apidoc: gagal menulis %s: %v\n", routesOut, err)
		os.Exit(1)
	}
	if err := writeFile(openapiOut, openapi); err != nil {
		fmt.Fprintf(os.Stderr, "apidoc: gagal menulis %s: %v\n", openapiOut, err)
		os.Exit(1)
	}
	fmt.Printf("apidoc: %d endpoint API (+%d statis) ditulis ke %s & %s\n",
		apiCount, len(routes)-apiCount, routesOut, openapiOut)
}

// parseRoutes membaca server.go baris per baris dan mengumpulkan seluruh rute.
func parseRoutes(path string) ([]route, error) {
	f, err := os.Open(path)
	if err != nil {
		return nil, err
	}
	defer func() { _ = f.Close() }()

	var routes []route
	scanner := bufio.NewScanner(f)
	// Longgarkan batas token agar baris panjang tidak terpotong.
	scanner.Buffer(make([]byte, 0, 64*1024), 1024*1024)
	lineNo := 0
	for scanner.Scan() {
		lineNo++
		line := scanner.Text()

		if m := handleFuncRe.FindStringSubmatch(line); m != nil {
			method := m[1]
			path := m[2]
			wrapper := strings.TrimSpace(m[3])
			routes = append(routes, route{
				Method:  method,
				Path:    path,
				Handler: handlerName(wrapper),
				Wrapper: wrapper,
				Auth:    classifyAuth(wrapper),
				Line:    lineNo,
				Static:  false,
			})
			continue
		}
		if m := handleRe.FindStringSubmatch(line); m != nil {
			routes = append(routes, route{
				Method:  m[1],
				Path:    m[2],
				Handler: "uploads (statis)",
				Wrapper: "http.FileServer",
				Auth:    "publik",
				Line:    lineNo,
				Static:  true,
			})
		}
	}
	if err := scanner.Err(); err != nil {
		return nil, err
	}
	return routes, nil
}

// handlerName mengambil nama handler terdalam dari ekspresi pembungkus.
//
//	s.requireAuth(s.register          -> register
//	s.rateLimit(s.login)              -> login
//	s.paymentWebhook                  -> paymentWebhook
func handlerName(wrapper string) string {
	name := wrapper
	if i := strings.LastIndex(name, "("); i >= 0 {
		name = name[i+1:]
	}
	name = strings.TrimPrefix(name, "s.")
	name = strings.TrimSuffix(name, ")")
	name = strings.TrimSpace(name)
	if name == "" {
		return wrapper
	}
	return name
}

// classifyAuth memetakan pembungkus terluar ke label autentikasi.
func classifyAuth(wrapper string) string {
	switch {
	case strings.HasPrefix(wrapper, "s.requireAdmin"):
		return "bearer (admin)"
	case strings.HasPrefix(wrapper, "s.requireAuth"):
		return "bearer"
	case strings.HasPrefix(wrapper, "s.public"):
		return "publik"
	case strings.HasPrefix(wrapper, "s.rateLimit"):
		// Seluruh endpoint ber-rate-limit adalah endpoint auth publik.
		return "publik"
	case strings.HasPrefix(wrapper, "s.paymentWebhook"):
		return "signature"
	case strings.HasPrefix(wrapper, "s.realtimeWS"):
		return "bearer (query token)"
	case strings.HasPrefix(wrapper, "s.root"), strings.HasPrefix(wrapper, "s.health"):
		return "publik"
	default:
		// Handler telanjang (mis. s.verifyEPrescriptionQR) bersifat publik.
		return "publik"
	}
}

// tagFor menurunkan tag dari segmen path pertama setelah /v1/.
func tagFor(path string) string {
	if strings.HasPrefix(path, "/uploads") {
		return "uploads"
	}
	if !strings.HasPrefix(path, "/v1/") {
		return "system"
	}
	rest := strings.TrimPrefix(path, "/v1/")
	if i := strings.IndexByte(rest, '/'); i >= 0 {
		return rest[:i]
	}
	if rest == "" {
		return "system"
	}
	return rest
}

// isBearer menentukan apakah operasi memakai skema bearerAuth.
func isBearer(auth string) bool {
	return auth == "bearer" || auth == "bearer (admin)" || auth == "bearer (query token)"
}

// orderedTags mengembalikan daftar tag unik sesuai urutan kemunculan pertama.
func orderedTags(routes []route) []string {
	seen := make(map[string]bool)
	var tags []string
	for _, r := range routes {
		t := tagFor(r.Path)
		if !seen[t] {
			seen[t] = true
			tags = append(tags, t)
		}
	}
	return tags
}

// renderMarkdown menyusun docs/API_ROUTES.md.
func renderMarkdown(routes []route) []byte {
	apiCount := 0
	staticCount := 0
	for _, r := range routes {
		if r.Static {
			staticCount++
		} else {
			apiCount++
		}
	}

	var b strings.Builder
	b.WriteString("# Inventaris Rute API Malva\n\n")
	b.WriteString("> **Dibuat otomatis oleh `go run ./cmd/apidoc` — jangan diedit manual.**\n")
	b.WriteString("> Sumber kebenaran: `backend/internal/server/server.go` (fungsi `Routes()`).\n")
	b.WriteString("> Regenerasi: `cd backend && go run ./cmd/apidoc`\n")
	b.WriteString("> Verifikasi sinkron: `cd backend && go run ./cmd/apidoc -check`\n\n")
	fmt.Fprintf(&b, "Total endpoint API: **%d** (+%d penyajian berkas statis `GET /uploads/`).\n\n", apiCount, staticCount)

	tags := orderedTags(routes)

	// Ringkasan per tag.
	b.WriteString("## Ringkasan per Tag\n\n")
	b.WriteString("| Tag | Jumlah Endpoint |\n")
	b.WriteString("|---|---:|\n")
	counts := make(map[string]int)
	for _, r := range routes {
		counts[tagFor(r.Path)]++
	}
	for _, t := range tags {
		fmt.Fprintf(&b, "| %s | %d |\n", t, counts[t])
	}
	b.WriteString("\n")

	// Tabel per tag.
	for _, t := range tags {
		fmt.Fprintf(&b, "## `%s`\n\n", t)
		b.WriteString("| Method | Path | Handler | Auth | Baris |\n")
		b.WriteString("|---|---|---|---|---:|\n")
		for _, r := range routes {
			if tagFor(r.Path) != t {
				continue
			}
			fmt.Fprintf(&b, "| %s | `%s` | %s | %s | %d |\n",
				r.Method, r.Path, r.Handler, r.Auth, r.Line)
		}
		b.WriteString("\n")
	}
	return []byte(b.String())
}

// renderOpenAPI menyusun docs/openapi.yaml (OpenAPI 3.0.3).
func renderOpenAPI(routes []route) []byte {
	var b strings.Builder
	b.WriteString("openapi: 3.0.3\n")
	b.WriteString("info:\n")
	b.WriteString("  title: Malva Mental Health API\n")
	b.WriteString("  version: v1\n")
	b.WriteString("  description: |-\n")
	b.WriteString("    Skema OpenAPI backend Malva. Dihasilkan otomatis oleh\n")
	b.WriteString("    `go run ./cmd/apidoc` dari `internal/server/server.go` — jangan diedit manual.\n")
	b.WriteString("servers:\n")
	b.WriteString("  - url: https://api.malva.web.id\n")
	b.WriteString("    description: Produksi\n")
	b.WriteString("  - url: http://localhost:8080\n")
	b.WriteString("    description: Pengembangan lokal\n")

	// tags unik.
	b.WriteString("tags:\n")
	for _, t := range orderedTags(routes) {
		fmt.Fprintf(&b, "  - name: %s\n", yamlScalar(t))
	}

	// paths: kelompokkan per path (urut kemunculan pertama), tiap path bisa
	// punya beberapa method (mis. GET publik + POST terautentikasi).
	b.WriteString("paths:\n")
	var pathOrder []string
	pathMethods := make(map[string][]route)
	for _, r := range routes {
		if _, ok := pathMethods[r.Path]; !ok {
			pathOrder = append(pathOrder, r.Path)
		}
		pathMethods[r.Path] = append(pathMethods[r.Path], r)
	}
	for _, p := range pathOrder {
		fmt.Fprintf(&b, "  %s:\n", yamlScalar(p))
		for _, r := range pathMethods[p] {
			fmt.Fprintf(&b, "    %s:\n", strings.ToLower(r.Method))
			fmt.Fprintf(&b, "      tags:\n        - %s\n", yamlScalar(tagFor(r.Path)))
			fmt.Fprintf(&b, "      summary: %s\n", yamlScalar(r.Handler))
			// Parameter path.
			params := pathParamRe.FindAllStringSubmatch(r.Path, -1)
			if len(params) > 0 {
				b.WriteString("      parameters:\n")
				for _, pm := range params {
					fmt.Fprintf(&b, "        - name: %s\n", yamlScalar(pm[1]))
					b.WriteString("          in: path\n")
					b.WriteString("          required: true\n")
					b.WriteString("          schema:\n")
					b.WriteString("            type: string\n")
				}
			}
			// Body permintaan (overlay hand-written untuk endpoint inti).
			writeRequestBody(&b, r.Method, r.Path)
			// Keamanan.
			if isBearer(r.Auth) {
				b.WriteString("      security:\n")
				b.WriteString("        - bearerAuth: []\n")
			}
			// Respons standar.
			b.WriteString("      responses:\n")
			writeResponseRef(&b, "200", "OK")
			writeResponseRef(&b, "400", "BadRequest")
			writeResponseRef(&b, "401", "Unauthorized")
			writeResponseRef(&b, "403", "Forbidden")
			writeResponseRef(&b, "404", "NotFound")
			writeResponseRef(&b, "422", "UnprocessableEntity")
			writeResponseRef(&b, "500", "InternalServerError")
		}
	}

	// components.
	b.WriteString("components:\n")
	b.WriteString("  securitySchemes:\n")
	b.WriteString("    bearerAuth:\n")
	b.WriteString("      type: http\n")
	b.WriteString("      scheme: bearer\n")
	b.WriteString("      bearerFormat: JWT\n")
	b.WriteString("  schemas:\n")
	b.WriteString("    Error:\n")
	b.WriteString("      type: object\n")
	b.WriteString("      properties:\n")
	b.WriteString("        error:\n")
	b.WriteString("          type: string\n")
	b.WriteString("      required:\n")
	b.WriteString("        - error\n")
	b.WriteString("  responses:\n")
	writeResponseDef(&b, "OK", "Permintaan berhasil.", false)
	writeResponseDef(&b, "BadRequest", "Permintaan tidak valid.", true)
	writeResponseDef(&b, "Unauthorized", "Token tidak ada atau tidak valid.", true)
	writeResponseDef(&b, "Forbidden", "Pengguna tidak berhak atas sumber daya ini.", true)
	writeResponseDef(&b, "NotFound", "Sumber daya tidak ditemukan.", true)
	writeResponseDef(&b, "UnprocessableEntity", "Data tidak dapat diproses.", true)
	writeResponseDef(&b, "InternalServerError", "Kesalahan internal server.", true)

	return []byte(b.String())
}

// writeResponseRef menulis satu entri respons yang menunjuk $ref komponen.
func writeResponseRef(b *strings.Builder, code, name string) {
	fmt.Fprintf(b, "        '%s':\n", code)
	fmt.Fprintf(b, "          $ref: '#/components/responses/%s'\n", name)
}

// writeResponseDef menulis definisi respons di bagian components.responses.
func writeResponseDef(b *strings.Builder, name, desc string, useError bool) {
	fmt.Fprintf(b, "    %s:\n", name)
	fmt.Fprintf(b, "      description: %s\n", yamlScalar(desc))
	b.WriteString("      content:\n")
	b.WriteString("        application/json:\n")
	b.WriteString("          schema:\n")
	if useError {
		b.WriteString("            $ref: '#/components/schemas/Error'\n")
	} else {
		b.WriteString("            type: object\n")
	}
}

// yamlScalar mengutip nilai scalar bila memuat karakter khusus YAML.
func yamlScalar(s string) string {
	if s == "" {
		return `""`
	}
	needQuote := false
	for _, r := range s {
		if !(r >= 'a' && r <= 'z') && !(r >= 'A' && r <= 'Z') &&
			!(r >= '0' && r <= '9') && r != '.' && r != '_' && r != '-' {
			needQuote = true
			break
		}
	}
	if !needQuote {
		return s
	}
	escaped := strings.ReplaceAll(s, `\`, `\\`)
	escaped = strings.ReplaceAll(escaped, `"`, `\"`)
	return `"` + escaped + `"`
}

// writeFile menulis data ke path, membuat folder induk bila perlu.
func writeFile(path string, data []byte) error {
	if err := os.MkdirAll(filepath.Dir(path), 0o755); err != nil {
		return err
	}
	return os.WriteFile(path, data, 0o644)
}

// checkFile membandingkan isi yang baru dihasilkan dengan berkas di disk.
func checkFile(path string, want []byte) error {
	got, err := os.ReadFile(path)
	if err != nil {
		return fmt.Errorf("%s belum ada atau tak terbaca: %w (jalankan go run ./cmd/apidoc)", path, err)
	}
	if !bytes.Equal(got, want) {
		return fmt.Errorf("%s tidak sinkron dengan server.go (jalankan go run ./cmd/apidoc)", path)
	}
	return nil
}

// bodyField mendeskripsikan satu field pada requestBody OpenAPI.
type bodyField struct {
	Name     string
	Type     string // string | integer | number | boolean | array
	ItemType string // tipe item bila Type == "array"
	Required bool
}

// requestBodies memetakan "METHOD /path" ke daftar field body. Diturunkan
// manual dari struct request NYATA: registerRequest, loginRequest,
// refreshTokenRequest, passwordChangeRequest, screeningRequest,
// moodCheckinRequest (internal/server/server.go), createBookingRequest,
// createPaymentRequest (handlers_booking.go), createCarePackageRequest,
// scheduleSessionRequest (handlers_care_packages.go), crisisAlertRequestV2
// (handlers_safety.go), dan payment.WebhookEvent (internal/payment).
// Endpoint yang tidak ada di sini tidak diberi requestBody.
var requestBodies = map[string][]bodyField{
	"POST /v1/auth/register": {
		{"email", "string", "", true},
		{"password", "string", "", true},
		{"display_name", "string", "", true},
		{"role", "string", "", true},
		{"professional_id", "string", "", false},
		{"phone", "string", "", false},
		{"date_of_birth", "string", "", false},
		{"gender", "string", "", false},
		{"str_number", "string", "", false},
		{"sip_number", "string", "", false},
		{"specialization", "string", "", false},
	},
	"POST /v1/auth/login": {
		{"email", "string", "", true},
		{"password", "string", "", true},
		{"professional_identifier", "string", "", false},
		{"role", "string", "", false},
	},
	"POST /v1/auth/refresh": {
		{"refresh_token", "string", "", true},
	},
	"POST /v1/auth/change-password": {
		{"current_password", "string", "", true},
		{"new_password", "string", "", true},
	},
	"POST /v1/screenings": {
		{"patient_id", "string", "", false},
		{"source", "string", "", false},
		{"is_initial", "boolean", "", false},
		{"phq9", "array", "integer", true},
		{"gad7", "array", "integer", true},
	},
	"POST /v1/mood-checkins": {
		{"mood", "string", "", true},
		{"sleep_hours", "number", "", false},
		{"energy", "integer", "", false},
		{"anxiety", "integer", "", false},
		{"irritability", "integer", "", false},
		{"note", "string", "", false},
		{"medication_taken", "boolean", "", false},
		{"occurred_at", "string", "", false},
	},
	"POST /v1/bookings": {
		{"patient_id", "string", "", false},
		{"professional_id", "string", "", false},
		{"package_id", "string", "", false},
		{"service_type", "string", "", true},
		{"session_type", "string", "", true},
		{"booking_date", "string", "", true},
		{"slot_time", "string", "", true},
		{"duration_minutes", "integer", "", true},
		{"price", "integer", "", false},
	},
	"POST /v1/payments": {
		{"booking_id", "string", "", true},
		{"payment_method", "string", "", false},
	},
	"POST /v1/care-packages": {
		{"professional_id", "string", "", true},
	},
	"POST /v1/care-sessions": {
		{"package_id", "string", "", true},
		{"scheduled_at", "string", "", true},
		{"session_type", "string", "", false},
		{"duration_minutes", "integer", "", false},
		{"meeting_url", "string", "", false},
	},
	"POST /v1/crisis-alerts": {
		{"triggered_by", "string", "", false},
		{"phq9_q9_score", "integer", "", false},
		{"latitude", "number", "", false},
		{"longitude", "number", "", false},
		{"message", "string", "", false},
		{"contact_phones", "array", "string", false},
	},
	"POST /v1/webhooks/payment": {
		{"order_id", "string", "", true},
		{"status_code", "string", "", true},
		{"gross_amount", "string", "", true},
		{"transaction_status", "string", "", true},
		{"fraud_status", "string", "", false},
		{"signature_key", "string", "", true},
		{"transaction_id", "string", "", false},
		{"payment_type", "string", "", false},
	},
}

// writeRequestBody menulis blok requestBody untuk endpoint yang ada di overlay.
func writeRequestBody(b *strings.Builder, method, path string) {
	fields, ok := requestBodies[method+" "+path]
	if !ok || len(fields) == 0 {
		return
	}
	b.WriteString("      requestBody:\n")
	b.WriteString("        required: true\n")
	b.WriteString("        content:\n")
	b.WriteString("          application/json:\n")
	b.WriteString("            schema:\n")
	b.WriteString("              type: object\n")
	b.WriteString("              properties:\n")
	for _, f := range fields {
		fmt.Fprintf(b, "                %s:\n", f.Name)
		if f.Type == "array" {
			b.WriteString("                  type: array\n")
			b.WriteString("                  items:\n")
			fmt.Fprintf(b, "                    type: %s\n", f.ItemType)
		} else {
			fmt.Fprintf(b, "                  type: %s\n", f.Type)
		}
	}
	reqs := make([]string, 0, len(fields))
	for _, f := range fields {
		if f.Required {
			reqs = append(reqs, f.Name)
		}
	}
	if len(reqs) > 0 {
		b.WriteString("              required:\n")
		for _, name := range reqs {
			fmt.Fprintf(b, "                - %s\n", name)
		}
	}
}
