# Inventaris Rute API Malva

> **Dibuat otomatis oleh `go run ./cmd/apidoc` — jangan diedit manual.**
> Sumber kebenaran: `backend/internal/server/server.go` (fungsi `Routes()`).
> Regenerasi: `cd backend && go run ./cmd/apidoc`
> Verifikasi sinkron: `cd backend && go run ./cmd/apidoc -check`

Total endpoint API: **123** (+1 penyajian berkas statis `GET /uploads/`).

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
| care-sessions | 6 |
| google | 1 |
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
| GET | `/` | root | publik | 204 |
| GET | `/healthz` | health | publik | 205 |

## `auth`

| Method | Path | Handler | Auth | Baris |
|---|---|---|---|---:|
| POST | `/v1/auth/register` | register | publik | 206 |
| POST | `/v1/auth/login` | login | publik | 207 |
| POST | `/v1/auth/google` | googleLogin | publik | 208 |
| POST | `/v1/auth/link-google` | linkGoogle | bearer | 209 |
| POST | `/v1/auth/google-token-exchange` | exchangeGoogleToken | bearer | 210 |
| POST | `/v1/auth/complete-professional` | completeProfessionalProfile | bearer | 211 |
| POST | `/v1/auth/refresh` | refresh | publik | 212 |
| POST | `/v1/auth/logout` | logout | publik | 213 |
| POST | `/v1/auth/change-password` | changePassword | bearer | 214 |

## `me`

| Method | Path | Handler | Auth | Baris |
|---|---|---|---|---:|
| GET | `/v1/me` | me | bearer | 215 |
| PATCH | `/v1/me` | updateMe | bearer | 216 |

## `device-tokens`

| Method | Path | Handler | Auth | Baris |
|---|---|---|---|---:|
| POST | `/v1/device-tokens` | upsertDeviceToken | bearer | 217 |

## `screenings`

| Method | Path | Handler | Auth | Baris |
|---|---|---|---|---:|
| POST | `/v1/screenings` | createScreening | bearer | 218 |
| GET | `/v1/screenings` | listScreenings | bearer | 219 |
| POST | `/v1/screenings/{screening_id}/review` | reviewScreening | bearer | 220 |

## `screening-reviews`

| Method | Path | Handler | Auth | Baris |
|---|---|---|---|---:|
| GET | `/v1/screening-reviews` | listScreeningReviews | bearer | 221 |

## `patient-professional-links`

| Method | Path | Handler | Auth | Baris |
|---|---|---|---|---:|
| GET | `/v1/patient-professional-links` | listPatientProfessionalLinks | bearer | 222 |
| POST | `/v1/patient-professional-links` | linkPatientToProfessional | bearer | 223 |

## `professional-notes`

| Method | Path | Handler | Auth | Baris |
|---|---|---|---|---:|
| GET | `/v1/professional-notes` | listProfessionalNotes | bearer | 224 |
| POST | `/v1/professional-notes` | createProfessionalNote | bearer | 225 |

## `follow-ups`

| Method | Path | Handler | Auth | Baris |
|---|---|---|---|---:|
| GET | `/v1/follow-ups` | listFollowUps | bearer | 226 |
| POST | `/v1/follow-ups` | createFollowUp | bearer | 227 |
| PATCH | `/v1/follow-ups/{follow_up_id}/read` | markFollowUpRead | bearer | 228 |

## `mood-checkins`

| Method | Path | Handler | Auth | Baris |
|---|---|---|---|---:|
| GET | `/v1/mood-checkins` | listMoodCheckins | bearer | 229 |
| POST | `/v1/mood-checkins` | createMoodCheckin | bearer | 230 |

## `diary-entries`

| Method | Path | Handler | Auth | Baris |
|---|---|---|---|---:|
| GET | `/v1/diary-entries` | listDiaryEntries | bearer | 231 |
| POST | `/v1/diary-entries` | createDiaryEntry | bearer | 232 |
| PUT | `/v1/diary-entries/{diary_id}` | updateDiaryEntry | bearer | 233 |
| DELETE | `/v1/diary-entries/{diary_id}` | deleteDiaryEntry | bearer | 234 |
| PATCH | `/v1/diary-entries/{diary_id}/feedback` | updateDiaryFeedback | bearer | 235 |

## `medications`

| Method | Path | Handler | Auth | Baris |
|---|---|---|---|---:|
| GET | `/v1/medications` | listMedications | bearer | 236 |
| POST | `/v1/medications` | createMedication | bearer | 237 |
| PUT | `/v1/medications/{medication_id}` | updateMedication | bearer | 241 |
| DELETE | `/v1/medications/{medication_id}` | deleteMedication | bearer | 242 |

## `medication-logs`

| Method | Path | Handler | Auth | Baris |
|---|---|---|---|---:|
| GET | `/v1/medication-logs` | listMedicationLogs | bearer | 243 |
| POST | `/v1/medication-logs` | createMedicationLog | bearer | 244 |

## `timeline`

| Method | Path | Handler | Auth | Baris |
|---|---|---|---|---:|
| GET | `/v1/timeline` | timeline | bearer | 245 |

## `audit-logs`

| Method | Path | Handler | Auth | Baris |
|---|---|---|---|---:|
| GET | `/v1/audit-logs` | auditLogs | bearer | 246 |

## `privacy`

| Method | Path | Handler | Auth | Baris |
|---|---|---|---|---:|
| GET | `/v1/privacy/consents` | getPrivacyConsent | bearer | 247 |
| PUT | `/v1/privacy/consents` | updatePrivacyConsent | bearer | 248 |

## `messages`

| Method | Path | Handler | Auth | Baris |
|---|---|---|---|---:|
| GET | `/v1/messages` | listMessages | bearer | 249 |
| POST | `/v1/messages` | sendMessage | bearer | 250 |

## `notifications`

| Method | Path | Handler | Auth | Baris |
|---|---|---|---|---:|
| GET | `/v1/notifications` | listNotifications | bearer | 251 |
| PATCH | `/v1/notifications/read-all` | markAllNotificationsRead | bearer | 252 |
| PATCH | `/v1/notifications/{notification_id}/read` | markNotificationRead | bearer | 253 |
| POST | `/v1/notifications/test` | testNotification | bearer | 254 |

## `realtime`

| Method | Path | Handler | Auth | Baris |
|---|---|---|---|---:|
| GET | `/v1/realtime/ws` | realtimeWS | bearer (query token) | 255 |

## `emergency-contacts`

| Method | Path | Handler | Auth | Baris |
|---|---|---|---|---:|
| GET | `/v1/emergency-contacts` | listEmergencyContacts | bearer | 257 |
| POST | `/v1/emergency-contacts` | createEmergencyContact | bearer | 258 |
| PUT | `/v1/emergency-contacts/{id}` | updateEmergencyContact | bearer | 259 |
| DELETE | `/v1/emergency-contacts/{id}` | deleteEmergencyContact | bearer | 260 |

## `crisis-alerts`

| Method | Path | Handler | Auth | Baris |
|---|---|---|---|---:|
| POST | `/v1/crisis-alerts` | handleCrisisAlertV2 | bearer | 261 |

## `crisis-incidents`

| Method | Path | Handler | Auth | Baris |
|---|---|---|---|---:|
| GET | `/v1/crisis-incidents` | listCrisisIncidents | bearer | 262 |
| POST | `/v1/crisis-incidents/{id}/resolve` | resolveCrisisIncident | bearer | 263 |

## `sos-blast-status`

| Method | Path | Handler | Auth | Baris |
|---|---|---|---|---:|
| GET | `/v1/sos-blast-status` | listBlastStatus | bearer | 264 |

## `credentials`

| Method | Path | Handler | Auth | Baris |
|---|---|---|---|---:|
| POST | `/v1/credentials` | uploadCredentials | bearer | 266 |
| GET | `/v1/credentials/me` | getMyCredentials | bearer | 267 |

## `upload`

| Method | Path | Handler | Auth | Baris |
|---|---|---|---|---:|
| POST | `/v1/upload` | uploadFile | bearer | 269 |

## `uploads`

| Method | Path | Handler | Auth | Baris |
|---|---|---|---|---:|
| GET | `/uploads/` | uploads (statis) | publik | 271 |

## `psych-tests`

| Method | Path | Handler | Auth | Baris |
|---|---|---|---|---:|
| GET | `/v1/psych-tests` | listPsychTests | publik | 273 |

## `doctors`

| Method | Path | Handler | Auth | Baris |
|---|---|---|---|---:|
| GET | `/v1/doctors/search` | searchDoctors | publik | 276 |
| GET | `/v1/doctors/{user_id}` | getDoctorProfile | publik | 277 |
| GET | `/v1/doctors/{user_id}/slots` | getDoctorAvailableSlots | publik | 278 |
| GET | `/v1/doctors/{user_id}/availability` | getDoctorAvailability | publik | 279 |
| GET | `/v1/doctors/{user_id}/reviews` | listDoctorReviews | publik | 316 |
| POST | `/v1/doctors/{user_id}/reviews` | createDoctorReview | bearer | 317 |

## `pricing`

| Method | Path | Handler | Auth | Baris |
|---|---|---|---|---:|
| GET | `/v1/pricing` | getPricing | bearer | 280 |

## `bookings`

| Method | Path | Handler | Auth | Baris |
|---|---|---|---|---:|
| POST | `/v1/bookings` | createBooking | bearer | 282 |
| POST | `/v1/bookings/{booking_id}/cancel` | cancelPendingBooking | bearer | 283 |
| GET | `/v1/bookings` | listBookings | bearer | 288 |

## `payments`

| Method | Path | Handler | Auth | Baris |
|---|---|---|---|---:|
| POST | `/v1/payments` | createPayment | bearer | 284 |
| POST | `/v1/payments/mark-paid` | markPaymentPaid | bearer | 285 |

## `webhooks`

| Method | Path | Handler | Auth | Baris |
|---|---|---|---|---:|
| POST | `/v1/webhooks/payment` | paymentWebhook | signature | 287 |

## `care-packages`

| Method | Path | Handler | Auth | Baris |
|---|---|---|---|---:|
| POST | `/v1/care-packages` | createCarePackage | bearer | 290 |
| GET | `/v1/care-packages` | listCarePackages | bearer | 291 |
| POST | `/v1/care-packages/{package_id}/cancel` | cancelPendingCarePackage | bearer | 292 |

## `care-sessions`

| Method | Path | Handler | Auth | Baris |
|---|---|---|---|---:|
| POST | `/v1/care-sessions` | scheduleSession | bearer | 293 |
| GET | `/v1/care-sessions` | listCareSessions | bearer | 294 |
| PATCH | `/v1/care-sessions/{session_id}` | updateCareSession | bearer | 295 |
| POST | `/v1/care-sessions/{session_id}/reschedule` | rescheduleCareSession | bearer | 296 |
| POST | `/v1/care-sessions/{session_id}/meet-link` | ensureMeetLinkHandler | bearer | 298 |
| POST | `/v1/care-sessions/{session_id}/refund` | refundCareSession | bearer | 304 |

## `google`

| Method | Path | Handler | Auth | Baris |
|---|---|---|---|---:|
| GET | `/v1/google/status` | googleStatusHandler | bearer | 300 |

## `meet`

| Method | Path | Handler | Auth | Baris |
|---|---|---|---|---:|
| POST | `/v1/meet/quick` | createQuickMeet | bearer | 302 |

## `care-refunds`

| Method | Path | Handler | Auth | Baris |
|---|---|---|---|---:|
| GET | `/v1/care-refunds` | listCareRefunds | bearer | 305 |

## `chat-permission`

| Method | Path | Handler | Auth | Baris |
|---|---|---|---|---:|
| GET | `/v1/chat-permission` | chatPermission | bearer | 306 |

## `professional`

| Method | Path | Handler | Auth | Baris |
|---|---|---|---|---:|
| GET | `/v1/professional/time-off` | listTimeOff | bearer | 308 |
| POST | `/v1/professional/time-off` | addTimeOff | bearer | 309 |
| DELETE | `/v1/professional/time-off/{id}` | deleteTimeOff | bearer | 310 |
| PUT | `/v1/professional/pricing` | updatePricing | bearer | 311 |
| GET | `/v1/professional/schedules` | listMySchedules | bearer | 312 |
| PUT | `/v1/professional/schedules` | updateMySchedules | bearer | 313 |
| DELETE | `/v1/professional/schedules/{id}` | deleteMySchedule | bearer | 315 |

## `earnings`

| Method | Path | Handler | Auth | Baris |
|---|---|---|---|---:|
| GET | `/v1/earnings` | earningsSummary | bearer | 318 |
| POST | `/v1/earnings/payout` | requestPayoutAll | bearer | 320 |
| POST | `/v1/earnings/{earning_id}/payout` | requestPayout | bearer | 321 |

## `e-prescriptions`

| Method | Path | Handler | Auth | Baris |
|---|---|---|---|---:|
| POST | `/v1/e-prescriptions` | createEPrescription | bearer | 322 |
| GET | `/v1/e-prescriptions` | listEPrescriptions | bearer | 323 |
| GET | `/v1/e-prescriptions/{id}` | getEPrescription | bearer | 324 |
| GET | `/v1/e-prescriptions/verify` | verifyEPrescriptionQR | publik | 326 |

## `health-record`

| Method | Path | Handler | Auth | Baris |
|---|---|---|---|---:|
| GET | `/v1/health-record` | getHealthRecord | bearer | 328 |
| PUT | `/v1/health-record` | updateHealthRecord | bearer | 329 |

## `goals`

| Method | Path | Handler | Auth | Baris |
|---|---|---|---|---:|
| GET | `/v1/goals` | listGoals | bearer | 331 |
| POST | `/v1/goals` | createGoal | bearer | 332 |
| PATCH | `/v1/goals/{goal_id}` | updateGoal | bearer | 333 |
| DELETE | `/v1/goals/{goal_id}` | deleteGoal | bearer | 334 |

## `habit-logs`

| Method | Path | Handler | Auth | Baris |
|---|---|---|---|---:|
| GET | `/v1/habit-logs` | listHabitLogs | bearer | 335 |
| POST | `/v1/habit-logs` | logHabit | bearer | 336 |

## `therapy-submissions`

| Method | Path | Handler | Auth | Baris |
|---|---|---|---|---:|
| GET | `/v1/therapy-submissions` | listTherapySubmissions | bearer | 338 |
| POST | `/v1/therapy-submissions` | createTherapySubmission | bearer | 339 |
| GET | `/v1/therapy-submissions/{submission_id}` | getTherapySubmission | bearer | 340 |
| POST | `/v1/therapy-submissions/{submission_id}/share` | shareTherapySubmission | bearer | 341 |
| DELETE | `/v1/therapy-submissions/{submission_id}` | deleteTherapySubmission | bearer | 342 |

## `admin`

| Method | Path | Handler | Auth | Baris |
|---|---|---|---|---:|
| GET | `/v1/admin/users` | listAdminUsers | bearer (admin) | 344 |
| PATCH | `/v1/admin/users/{user_id}` | updateAdminUser | bearer (admin) | 345 |
| DELETE | `/v1/admin/users/{user_id}` | deleteAdminUser | bearer (admin) | 346 |
| GET | `/v1/admin/credentials/pending` | listPendingCredentials | bearer (admin) | 347 |
| POST | `/v1/admin/credentials/{id}/verify` | verifyCredential | bearer (admin) | 348 |
| POST | `/v1/admin/doctors` | createAdminDoctor | bearer (admin) | 349 |
| GET | `/v1/admin/doctors` | listAdminDoctors | bearer (admin) | 350 |
| GET | `/v1/admin/doctors/{user_id}` | getAdminDoctor | bearer (admin) | 351 |
| PUT | `/v1/admin/doctors/{user_id}` | updateAdminDoctor | bearer (admin) | 352 |

