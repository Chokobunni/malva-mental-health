package main

import (
	"fmt"
	"strings"
)

func writeGoalsQueryParameters(b *strings.Builder) {
	b.WriteString(`      parameters:
        - name: on
          in: query
          description: Tanggal pilihan WIB; default hari ini.
          schema:
            type: string
            format: date
        - name: include_inactive
          in: query
          schema:
            type: boolean
            default: false
        - name: patient_id
          in: query
          description: Pasien sendiri atau pasien berelasi dan berizin untuk profesional.
          schema:
            type: string
            format: uuid
`)
}

func writeGoalRequestBody(b *strings.Builder, method, path string) bool {
	schema := ""
	switch method + " " + path {
	case "POST /v1/goals":
		schema = "GoalCreateRequest"
	case "PATCH /v1/goals/{goal_id}":
		schema = "GoalWriteRequest"
	case "POST /v1/habit-logs":
		schema = "HabitLogRequest"
	default:
		return false
	}
	fmt.Fprintf(b, "      requestBody:\n        required: true\n        content:\n          application/json:\n            schema:\n              $ref: '#/components/schemas/%s'\n", schema)
	return true
}

func writeGoalResponse(b *strings.Builder, method, path string) bool {
	schema := ""
	status := "200"
	switch method + " " + path {
	case "GET /v1/goals":
		schema = "GoalListResponse"
	case "POST /v1/goals":
		schema = "GoalResponse"
		status = "201"
	case "PATCH /v1/goals/{goal_id}":
		schema = "GoalResponse"
	case "POST /v1/habit-logs":
		schema = "HabitLogResponse"
	case "GET /v1/habit-logs":
		schema = "HabitLogListResponse"
	default:
		return false
	}
	fmt.Fprintf(b, "        '%s':\n          description: Permintaan berhasil.\n          content:\n            application/json:\n              schema:\n                $ref: '#/components/schemas/%s'\n", status, schema)
	return true
}

const goalSchemas = `    GoalDetails:
      type: object
      description: Konfigurasi opsional; null/absen mempertahankan goal yes/no legacy. PATCH tanpa details mempertahankan konfigurasi tersimpan.
      required: [method, start_date, recurrence, interval]
      properties:
        note:
          type: string
          maxLength: 5000
        method:
          type: string
          enum: [yes_no, numeric, checklist]
        target:
          type: integer
          minimum: 0
          maximum: 1000000
          description: Wajib 1–1000000 untuk metode numeric.
        unit:
          type: string
          maxLength: 80
        steps:
          type: array
          maxItems: 100
          description: ID unik dan stabil; checklist memerlukan minimal satu langkah.
          items:
            type: object
            required: [id, label]
            properties:
              id:
                type: string
                minLength: 1
                maxLength: 64
              label:
                type: string
                minLength: 1
                maxLength: 500
        start_date:
          type: string
          format: date
        time:
          type: string
          description: HH:mm WIB atau kosong untuk tanpa pengingat terjadwal.
          pattern: '^([01][0-9]|2[0-3]):[0-5][0-9]$|^$'
        recurrence:
          type: string
          enum: [daily, weekly, monthly]
        interval:
          type: integer
          minimum: 1
          maximum: 365
          description: Hari untuk daily (maksimal 365), minggu untuk weekly (maksimal 52), bulan untuk monthly (maksimal 12). Minggu dimulai Senin pada minggu start_date. Monthly mengikuti tanggal start_date, dijepit ke akhir bulan pendek lalu kembali ke tanggal asal.
        weekly_target:
          type: integer
          minimum: 0
          maximum: 7
          description: Opsional, hanya weekly. Jika hadir, goal fleksibel pada setiap hari minggu aktif; 0 tanpa kuota. Jika absen gunakan weekdays. Tidak mengubah target_per_week legacy.
        weekdays:
          type: array
          uniqueItems: true
          maxItems: 7
          description: ISO Senin=1 sampai Minggu=7; weekly tanpa weekly_target wajib minimal satu hari.
          items:
            type: integer
            minimum: 1
            maximum: 7
        reminders:
          type: array
          uniqueItems: true
          maxItems: 10
          description: Offset menit sebelum jam goal; notifikasi lokal perangkat.
          items:
            type: integer
            minimum: 0
            maximum: 10080
        auto_fail:
          type: boolean
          description: Occurrence terjadwal yang lewat tanpa log dianggap gagal tanpa menyisipkan log sintetis.
        lock_past:
          type: boolean
          description: Tolak log sebelum kemarin WIB; kemarin boleh diubah sampai akhir hari ini.
    GoalWriteRequest:
      type: object
      properties:
        title:
          type: string
          maxLength: 200
        category:
          type: string
        target_per_week:
          type: integer
          description: Target legacy dipertahankan; rentang efektif 1–7.
        is_active:
          type: boolean
        patient_id:
          type: string
          format: uuid
        details:
          allOf:
            - $ref: '#/components/schemas/GoalDetails'
          nullable: true
    GoalCreateRequest:
      allOf:
        - $ref: '#/components/schemas/GoalWriteRequest'
        - type: object
          required: [title]
    HabitLogRequest:
      type: object
      required: [goal_id]
      description: Patch independen; field progress yang absen dipertahankan. Goal terkonfigurasi menolak tanggal mendatang/tidak terjadwal dan mematuhi lock_past.
      properties:
        goal_id:
          type: string
          format: uuid
        logged_on:
          type: string
          format: date
          description: Default hari ini WIB.
        date:
          type: string
          format: date
          description: Alias kompatibilitas jika logged_on kosong.
        done:
          type: boolean
          description: Default true untuk yes/no. Numeric/checklist dihitung dari target/seluruh langkah saat ini.
        value:
          type: integer
          minimum: 0
          maximum: 1000000
        completed_step_ids:
          type: array
          maxItems: 100
          uniqueItems: true
          description: Hanya ID langkah pada goal ini; array kosong menghapus progress langkah.
          items:
            type: string
            maxLength: 64
    Goal:
      allOf:
        - $ref: '#/components/schemas/GoalWriteRequest'
        - type: object
          properties:
            id:
              type: string
              format: uuid
            sort_order:
              type: integer
            created_at:
              type: string
              format: date-time
            updated_at:
              type: string
              format: date-time
            done_this_week:
              type: integer
            completed_weekdays:
              type: array
              uniqueItems: true
              description: Hari ISO terurut dengan log sukses yang terjadwal pada minggu pilihan sampai tanggal on; tidak mengisi hari tanpa log.
              items:
                type: integer
                minimum: 1
                maximum: 7
            last_logged_on:
              type: string
              format: date
            done_today:
              type: boolean
              description: Penyelesaian pada tanggal on yang dipilih, memakai target/langkah goal saat ini.
            today_value:
              type: integer
              description: Progress tanggal on; nol bila belum dicatat.
            today_completed_step_ids:
              type: array
              items:
                type: string
            streak_days:
              type: integer
              description: Jumlah hari habit sukses berturut-turut; lewati hari tidak terjadwal dan izinkan hari ini belum dicatat. Log gagal eksplisit memutus streak; log hilang memutus hanya bila auto_fail. Weekly fleksibel memutus hanya setelah minggu aktif selesai di bawah kuota; kuota 0 mengabaikan log hilang.
            is_due:
              type: boolean
            failed_today:
              type: boolean
              description: Log belum selesai atau occurrence hilang yang sudah lewat dengan auto_fail, pada tanggal on. Weekly fleksibel tidak menggagalkan hari istirahat tanpa log.
    HabitLog:
      type: object
      properties:
        id:
          type: string
          format: uuid
        goal_id:
          type: string
          format: uuid
        patient_id:
          type: string
          format: uuid
        logged_on:
          type: string
          format: date
        done:
          type: boolean
        value:
          type: integer
        completed_step_ids:
          type: array
          items:
            type: string
        created_at:
          type: string
          format: date-time
    GoalResponse:
      type: object
      properties:
        goal:
          $ref: '#/components/schemas/Goal'
    GoalListResponse:
      type: object
      properties:
        goals:
          type: array
          items:
            $ref: '#/components/schemas/Goal'
    HabitLogResponse:
      type: object
      properties:
        log:
          $ref: '#/components/schemas/HabitLog'
    HabitLogListResponse:
      type: object
      properties:
        logs:
          type: array
          items:
            $ref: '#/components/schemas/HabitLog'
`
