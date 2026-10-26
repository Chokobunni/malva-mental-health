# Inventaris Rute API Malva

> **Dibuat otomatis oleh `go run ./cmd/apidoc` — jangan diedit manual.**
> Sumber kebenaran: `backend/internal/server/server.go` (fungsi `Routes()`).
> Regenerasi: `cd backend && go run ./cmd/apidoc`
> Verifikasi sinkron: `cd backend && go run ./cmd/apidoc -check`

Total endpoint API: **121** (+1 penyajian berkas statis `GET /uploads/`).

## Ringkasan per Tag

| Tag | Jumlah Endpoint |
|---|---:|
| system | 2 |
| auth | 9 |
| me | 2 |
| device-tokens | 1 |
| screenings | 3 |
| screening-reviews | 1 |
| patient-professional-links | 2 |
| professional-notes | 2 |
| follow-ups | 3 |
| mood-checkins | 2 |
| diary-entries | 5 |
| medications | 4 |
| medication-logs | 2 |
| timeline | 1 |
| audit-logs | 1 |
| privacy | 2 |
| messages | 2 |
| notifications | 4 |
| realtime | 1 |
| emergency-contacts | 4 |
| crisis-alerts | 1 |
| crisis-incidents | 2 |
| sos-blast-status | 1 |
| credentials | 2 |
| upload | 1 |
| uploads | 1 |
| psych-tests | 1 |
| doctors | 6 |
| pricing | 1 |
| bookings | 3 |
| payments | 2 |
| webhooks | 1 |
| care-packages | 3 |
| care-sessions | 5 |
| meet | 1 |
| care-refunds | 1 |
| chat-permission | 1 |
| professional | 7 |
| earnings | 3 |
| e-prescriptions | 4 |
| health-record | 2 |
| goals | 4 |
| habit-logs | 2 |
| therapy-submissions | 5 |
| admin | 9 |

## `system`

| Method | Path | Handler | Auth | Baris |
|---|---|---|---|---:|
| GET | `/` | root | publik | 203 |
| GET | `/healthz` | health | publik | 204 |

## `auth`

| Method | Path | Handler | Auth | Baris |
|---|---|---|---|---:|
| POST | `/v1/auth/register` | register | publik | 205 |
| POST | `/v1/auth/login` | login | publik | 206 |
| POST | `/v1/auth/google` | googleLogin | publik | 207 |
| POST | `/v1/auth/link-google` | linkGoogle | bearer | 208 |
| POST | `/v1/auth/google-token-exchange` | exchangeGoogleToken | bearer | 209 |
| POST | `/v1/auth/complete-professional` | completeProfessionalProfile | bearer | 210 |
| POST | `/v1/auth/refresh` | refresh | publik | 211 |
| POST | `/v1/auth/logout` | logout | publik | 212 |
| POST | `/v1/auth/change-password` | changePassword | bearer | 213 |

## `me`

| Method | Path | Handler | Auth | Baris |
|---|---|---|---|---:|
| GET | `/v1/me` | me | bearer | 214 |
| PATCH | `/v1/me` | updateMe | bearer | 215 |

## `device-tokens`

| Method | Path | Handler | Auth | Baris |
|---|---|---|---|---:|
| POST | `/v1/device-tokens` | upsertDeviceToken | bearer | 216 |

## `screenings`

| Method | Path | Handler | Auth | Baris |
|---|---|---|---|---:|
| POST | `/v1/screenings` | createScreening | bearer | 217 |
| GET | `/v1/screenings` | listScreenings | bearer | 218 |
| POST | `/v1/screenings/{screening_id}/review` | reviewScreening | bearer | 219 |

## `screening-reviews`

| Method | Path | Handler | Auth | Baris |
|---|---|---|---|---:|
| GET | `/v1/screening-reviews` | listScreeningReviews | bearer | 220 |

## `patient-professional-links`

| Method | Path | Handler | Auth | Baris |
|---|---|---|---|---:|
| GET | `/v1/patient-professional-links` | listPatientProfessionalLinks | bearer | 221 |
| POST | `/v1/patient-professional-links` | linkPatientToProfessional | bearer | 222 |

## `professional-notes`

| Method | Path | Handler | Auth | Baris |
|---|---|---|---|---:|
| GET | `/v1/professional-notes` | listProfessionalNotes | bearer | 223 |
| POST | `/v1/professional-notes` | createProfessionalNote | bearer | 224 |

## `follow-ups`

| Method | Path | Handler | Auth | Baris |
|---|---|---|---|---:|
| GET | `/v1/follow-ups` | listFollowUps | bearer | 225 |
| POST | `/v1/follow-ups` | createFollowUp | bearer | 226 |
| PATCH | `/v1/follow-ups/{follow_up_id}/read` | markFollowUpRead | bearer | 227 |

## `mood-checkins`

| Method | Path | Handler | Auth | Baris |
|---|---|---|---|---:|
| GET | `/v1/mood-checkins` | listMoodCheckins | bearer | 228 |
| POST | `/v1/mood-checkins` | createMoodCheckin | bearer | 229 |

## `diary-entries`

| Method | Path | Handler | Auth | Baris |
|---|---|---|---|---:|
| GET | `/v1/diary-entries` | listDiaryEntries | bearer | 230 |
| POST | `/v1/diary-entries` | createDiaryEntry | bearer | 231 |
| PUT | `/v1/diary-entries/{diary_id}` | updateDiaryEntry | bearer | 232 |
| DELETE | `/v1/diary-entries/{diary_id}` | deleteDiaryEntry | bearer | 233 |
| PATCH | `/v1/diary-entries/{diary_id}/feedback` | updateDiaryFeedback | bearer | 234 |

## `medications`

| Method | Path | Handler | Auth | Baris |
|---|---|---|---|---:|
| GET | `/v1/medications` | listMedications | bearer | 235 |
| POST | `/v1/medications` | createMedication | bearer | 236 |
| PUT | `/v1/medications/{medication_id}` | updateMedication | bearer | 240 |
| DELETE | `/v1/medications/{medication_id}` | deleteMedication | bearer | 241 |

## `medication-logs`

| Method | Path | Handler | Auth | Baris |
|---|---|---|---|---:|
| GET | `/v1/medication-logs` | listMedicationLogs | bearer | 242 |
| POST | `/v1/medication-logs` | createMedicationLog | bearer | 243 |

## `timeline`

| Method | Path | Handler | Auth | Baris |
|---|---|---|---|---:|
| GET | `/v1/timeline` | timeline | bearer | 244 |

## `audit-logs`

| Method | Path | Handler | Auth | Baris |
|---|---|---|---|---:|
| GET | `/v1/audit-logs` | auditLogs | bearer | 245 |

## `privacy`

| Method | Path | Handler | Auth | Baris |
|---|---|---|---|---:|
| GET | `/v1/privacy/consents` | getPrivacyConsent | bearer | 246 |
| PUT | `/v1/privacy/consents` | updatePrivacyConsent | bearer | 247 |

## `messages`

| Method | Path | Handler | Auth | Baris |
|---|---|---|---|---:|
| GET | `/v1/messages` | listMessages | bearer | 248 |
| POST | `/v1/messages` | sendMessage | bearer | 249 |

## `notifications`

| Method | Path | Handler | Auth | Baris |
|---|---|---|---|---:|
| GET | `/v1/notifications` | listNotifications | bearer | 250 |
| PATCH | `/v1/notifications/read-all` | markAllNotificationsRead | bearer | 251 |
| PATCH | `/v1/notifications/{notification_id}/read` | markNotificationRead | bearer | 252 |
| POST | `/v1/notifications/test` | testNotification | bearer | 253 |

## `realtime`

| Method | Path | Handler | Auth | Baris |
|---|---|---|---|---:|
| GET | `/v1/realtime/ws` | realtimeWS | bearer (query token) | 254 |

## `emergency-contacts`

| Method | Path | Handler | Auth | Baris |
|---|---|---|---|---:|
| GET | `/v1/emergency-contacts` | listEmergencyContacts | bearer | 256 |
| POST | `/v1/emergency-contacts` | createEmergencyContact | bearer | 257 |
| PUT | `/v1/emergency-contacts/{id}` | updateEmergencyContact | bearer | 258 |
| DELETE | `/v1/emergency-contacts/{id}` | deleteEmergencyContact | bearer | 259 |

## `crisis-alerts`

| Method | Path | Handler | Auth | Baris |
|---|---|---|---|---:|
| POST | `/v1/crisis-alerts` | handleCrisisAlertV2 | bearer | 260 |

## `crisis-incidents`

| Method | Path | Handler | Auth | Baris |
|---|---|---|---|---:|
| GET | `/v1/crisis-incidents` | listCrisisIncidents | bearer | 261 |
| POST | `/v1/crisis-incidents/{id}/resolve` | resolveCrisisIncident | bearer | 262 |

## `sos-blast-status`

| Method | Path | Handler | Auth | Baris |
|---|---|---|---|---:|
| GET | `/v1/sos-blast-status` | listBlastStatus | bearer | 263 |

## `credentials`

| Method | Path | Handler | Auth | Baris |
|---|---|---|---|---:|
| POST | `/v1/credentials` | uploadCredentials | bearer | 265 |
| GET | `/v1/credentials/me` | getMyCredentials | bearer | 266 |

## `upload`

| Method | Path | Handler | Auth | Baris |
|---|---|---|---|---:|
| POST | `/v1/upload` | uploadFile | bearer | 268 |

## `uploads`

| Method | Path | Handler | Auth | Baris |
|---|---|---|---|---:|
| GET | `/uploads/` | uploads (statis) | publik | 270 |

## `psych-tests`

| Method | Path | Handler | Auth | Baris |
|---|---|---|---|---:|
| GET | `/v1/psych-tests` | listPsychTests | publik | 272 |

## `doctors`

| Method | Path | Handler | Auth | Baris |
|---|---|---|---|---:|
| GET | `/v1/doctors/search` | searchDoctors | publik | 275 |
| GET | `/v1/doctors/{user_id}` | getDoctorProfile | publik | 276 |
| GET | `/v1/doctors/{user_id}/slots` | getDoctorAvailableSlots | publik | 277 |
| GET | `/v1/doctors/{user_id}/availability` | getDoctorAvailability | publik | 278 |
| GET | `/v1/doctors/{user_id}/reviews` | listDoctorReviews | publik | 311 |
| POST | `/v1/doctors/{user_id}/reviews` | createDoctorReview | bearer | 312 |

## `pricing`

| Method | Path | Handler | Auth | Baris |
|---|---|---|---|---:|
| GET | `/v1/pricing` | getPricing | bearer | 279 |

## `bookings`

| Method | Path | Handler | Auth | Baris |
|---|---|---|---|---:|
| POST | `/v1/bookings` | createBooking | bearer | 281 |
| POST | `/v1/bookings/{booking_id}/cancel` | cancelPendingBooking | bearer | 282 |
| GET | `/v1/bookings` | listBookings | bearer | 287 |

## `payments`

| Method | Path | Handler | Auth | Baris |
|---|---|---|---|---:|
| POST | `/v1/payments` | createPayment | bearer | 283 |
| POST | `/v1/payments/mark-paid` | markPaymentPaid | bearer | 284 |

## `webhooks`

| Method | Path | Handler | Auth | Baris |
|---|---|---|---|---:|
| POST | `/v1/webhooks/payment` | paymentWebhook | signature | 286 |

## `care-packages`

| Method | Path | Handler | Auth | Baris |
|---|---|---|---|---:|
| POST | `/v1/care-packages` | createCarePackage | bearer | 289 |
| GET | `/v1/care-packages` | listCarePackages | bearer | 290 |
| POST | `/v1/care-packages/{package_id}/cancel` | cancelPendingCarePackage | bearer | 291 |

## `care-sessions`

| Method | Path | Handler | Auth | Baris |
|---|---|---|---|---:|
| POST | `/v1/care-sessions` | scheduleSession | bearer | 292 |
| GET | `/v1/care-sessions` | listCareSessions | bearer | 293 |
| PATCH | `/v1/care-sessions/{session_id}` | updateCareSession | bearer | 294 |
| POST | `/v1/care-sessions/{session_id}/reschedule` | rescheduleCareSession | bearer | 295 |
| POST | `/v1/care-sessions/{session_id}/refund` | refundCareSession | bearer | 299 |

## `meet`

| Method | Path | Handler | Auth | Baris |
|---|---|---|---|---:|
| POST | `/v1/meet/quick` | createQuickMeet | bearer | 297 |

## `care-refunds`

| Method | Path | Handler | Auth | Baris |
|---|---|---|---|---:|
| GET | `/v1/care-refunds` | listCareRefunds | bearer | 300 |

## `chat-permission`

| Method | Path | Handler | Auth | Baris |
|---|---|---|---|---:|
| GET | `/v1/chat-permission` | chatPermission | bearer | 301 |

## `professional`

| Method | Path | Handler | Auth | Baris |
|---|---|---|---|---:|
| GET | `/v1/professional/time-off` | listTimeOff | bearer | 303 |
| POST | `/v1/professional/time-off` | addTimeOff | bearer | 304 |
| DELETE | `/v1/professional/time-off/{id}` | deleteTimeOff | bearer | 305 |
| PUT | `/v1/professional/pricing` | updatePricing | bearer | 306 |
| GET | `/v1/professional/schedules` | listMySchedules | bearer | 307 |
| PUT | `/v1/professional/schedules` | updateMySchedules | bearer | 308 |
| DELETE | `/v1/professional/schedules/{id}` | deleteMySchedule | bearer | 310 |

## `earnings`

| Method | Path | Handler | Auth | Baris |
|---|---|---|---|---:|
| GET | `/v1/earnings` | earningsSummary | bearer | 313 |
| POST | `/v1/earnings/payout` | requestPayoutAll | bearer | 315 |
| POST | `/v1/earnings/{earning_id}/payout` | requestPayout | bearer | 316 |

## `e-prescriptions`

| Method | Path | Handler | Auth | Baris |
|---|---|---|---|---:|
| POST | `/v1/e-prescriptions` | createEPrescription | bearer | 317 |
| GET | `/v1/e-prescriptions` | listEPrescriptions | bearer | 318 |
| GET | `/v1/e-prescriptions/{id}` | getEPrescription | bearer | 319 |
| GET | `/v1/e-prescriptions/verify` | verifyEPrescriptionQR | publik | 321 |

## `health-record`

| Method | Path | Handler | Auth | Baris |
|---|---|---|---|---:|
| GET | `/v1/health-record` | getHealthRecord | bearer | 323 |
| PUT | `/v1/health-record` | updateHealthRecord | bearer | 324 |

## `goals`

| Method | Path | Handler | Auth | Baris |
|---|---|---|---|---:|
| GET | `/v1/goals` | listGoals | bearer | 326 |
| POST | `/v1/goals` | createGoal | bearer | 327 |
| PATCH | `/v1/goals/{goal_id}` | updateGoal | bearer | 328 |
| DELETE | `/v1/goals/{goal_id}` | deleteGoal | bearer | 329 |

## `habit-logs`

| Method | Path | Handler | Auth | Baris |
|---|---|---|---|---:|
| GET | `/v1/habit-logs` | listHabitLogs | bearer | 330 |
| POST | `/v1/habit-logs` | logHabit | bearer | 331 |

## `therapy-submissions`

| Method | Path | Handler | Auth | Baris |
|---|---|---|---|---:|
| GET | `/v1/therapy-submissions` | listTherapySubmissions | bearer | 333 |
| POST | `/v1/therapy-submissions` | createTherapySubmission | bearer | 334 |
| GET | `/v1/therapy-submissions/{submission_id}` | getTherapySubmission | bearer | 335 |
| POST | `/v1/therapy-submissions/{submission_id}/share` | shareTherapySubmission | bearer | 336 |
| DELETE | `/v1/therapy-submissions/{submission_id}` | deleteTherapySubmission | bearer | 337 |

## `admin`

| Method | Path | Handler | Auth | Baris |
|---|---|---|---|---:|
| GET | `/v1/admin/users` | listAdminUsers | bearer (admin) | 339 |
| PATCH | `/v1/admin/users/{user_id}` | updateAdminUser | bearer (admin) | 340 |
| DELETE | `/v1/admin/users/{user_id}` | deleteAdminUser | bearer (admin) | 341 |
| GET | `/v1/admin/credentials/pending` | listPendingCredentials | bearer (admin) | 342 |
| POST | `/v1/admin/credentials/{id}/verify` | verifyCredential | bearer (admin) | 343 |
| POST | `/v1/admin/doctors` | createAdminDoctor | bearer (admin) | 344 |
| GET | `/v1/admin/doctors` | listAdminDoctors | bearer (admin) | 345 |
| GET | `/v1/admin/doctors/{user_id}` | getAdminDoctor | bearer (admin) | 346 |
| PUT | `/v1/admin/doctors/{user_id}` | updateAdminDoctor | bearer (admin) | 347 |

