# Inventaris Rute API Malva

> **Dibuat otomatis oleh `go run ./cmd/apidoc` — jangan diedit manual.**
> Sumber kebenaran: `backend/internal/server/server.go` (fungsi `Routes()`).
> Regenerasi: `cd backend && go run ./cmd/apidoc`
> Verifikasi sinkron: `cd backend && go run ./cmd/apidoc -check`

Total endpoint API: **130** (+1 penyajian berkas statis `GET /uploads/`).

## Ringkasan per Tag

| Tag | Jumlah Endpoint |
|---|---:|
| system | 2 |
| auth | 12 |
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
| payments | 3 |
| config | 1 |
| webhooks | 1 |
| care-packages | 3 |
| care-sessions | 7 |
| google | 1 |
| professionals | 1 |
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
| GET | `/` | root | publik | 208 |
| GET | `/healthz` | health | publik | 209 |

## `auth`

| Method | Path | Handler | Auth | Baris |
|---|---|---|---|---:|
| POST | `/v1/auth/register` | register | publik | 210 |
| POST | `/v1/auth/login` | login | publik | 211 |
| POST | `/v1/auth/google` | googleLogin | publik | 212 |
| POST | `/v1/auth/link-google` | linkGoogle | bearer | 213 |
| POST | `/v1/auth/bind-google` | bindGoogle | bearer | 214 |
| POST | `/v1/auth/unbind-google` | unbindGoogle | bearer | 215 |
| GET | `/v1/auth/google-identity` | googleIdentityStatus | bearer | 216 |
| POST | `/v1/auth/google-token-exchange` | exchangeGoogleToken | bearer | 217 |
| POST | `/v1/auth/complete-professional` | completeProfessionalProfile | bearer | 218 |
| POST | `/v1/auth/refresh` | refresh | publik | 219 |
| POST | `/v1/auth/logout` | logout | publik | 220 |
| POST | `/v1/auth/change-password` | changePassword | bearer | 221 |

## `me`

| Method | Path | Handler | Auth | Baris |
|---|---|---|---|---:|
| GET | `/v1/me` | me | bearer | 222 |
| PATCH | `/v1/me` | updateMe | bearer | 223 |

## `device-tokens`

| Method | Path | Handler | Auth | Baris |
|---|---|---|---|---:|
| POST | `/v1/device-tokens` | upsertDeviceToken | bearer | 224 |

## `screenings`

| Method | Path | Handler | Auth | Baris |
|---|---|---|---|---:|
| POST | `/v1/screenings` | createScreening | bearer | 225 |
| GET | `/v1/screenings` | listScreenings | bearer | 226 |
| POST | `/v1/screenings/{screening_id}/review` | reviewScreening | bearer | 227 |

## `screening-reviews`

| Method | Path | Handler | Auth | Baris |
|---|---|---|---|---:|
| GET | `/v1/screening-reviews` | listScreeningReviews | bearer | 228 |

## `patient-professional-links`

| Method | Path | Handler | Auth | Baris |
|---|---|---|---|---:|
| GET | `/v1/patient-professional-links` | listPatientProfessionalLinks | bearer | 229 |
| POST | `/v1/patient-professional-links` | linkPatientToProfessional | bearer | 230 |

## `professional-notes`

| Method | Path | Handler | Auth | Baris |
|---|---|---|---|---:|
| GET | `/v1/professional-notes` | listProfessionalNotes | bearer | 231 |
| POST | `/v1/professional-notes` | createProfessionalNote | bearer | 232 |

## `follow-ups`

| Method | Path | Handler | Auth | Baris |
|---|---|---|---|---:|
| GET | `/v1/follow-ups` | listFollowUps | bearer | 233 |
| POST | `/v1/follow-ups` | createFollowUp | bearer | 234 |
| PATCH | `/v1/follow-ups/{follow_up_id}/read` | markFollowUpRead | bearer | 235 |

## `mood-checkins`

| Method | Path | Handler | Auth | Baris |
|---|---|---|---|---:|
| GET | `/v1/mood-checkins` | listMoodCheckins | bearer | 236 |
| POST | `/v1/mood-checkins` | createMoodCheckin | bearer | 237 |

## `diary-entries`

| Method | Path | Handler | Auth | Baris |
|---|---|---|---|---:|
| GET | `/v1/diary-entries` | listDiaryEntries | bearer | 238 |
| POST | `/v1/diary-entries` | createDiaryEntry | bearer | 239 |
| PUT | `/v1/diary-entries/{diary_id}` | updateDiaryEntry | bearer | 240 |
| DELETE | `/v1/diary-entries/{diary_id}` | deleteDiaryEntry | bearer | 241 |
| PATCH | `/v1/diary-entries/{diary_id}/feedback` | updateDiaryFeedback | bearer | 242 |

## `medications`

| Method | Path | Handler | Auth | Baris |
|---|---|---|---|---:|
| GET | `/v1/medications` | listMedications | bearer | 243 |
| POST | `/v1/medications` | createMedication | bearer | 244 |
| PUT | `/v1/medications/{medication_id}` | updateMedication | bearer | 248 |
| DELETE | `/v1/medications/{medication_id}` | deleteMedication | bearer | 249 |

## `medication-logs`

| Method | Path | Handler | Auth | Baris |
|---|---|---|---|---:|
| GET | `/v1/medication-logs` | listMedicationLogs | bearer | 250 |
| POST | `/v1/medication-logs` | createMedicationLog | bearer | 251 |

## `timeline`

| Method | Path | Handler | Auth | Baris |
|---|---|---|---|---:|
| GET | `/v1/timeline` | timeline | bearer | 252 |

## `audit-logs`

| Method | Path | Handler | Auth | Baris |
|---|---|---|---|---:|
| GET | `/v1/audit-logs` | auditLogs | bearer | 253 |

## `privacy`

| Method | Path | Handler | Auth | Baris |
|---|---|---|---|---:|
| GET | `/v1/privacy/consents` | getPrivacyConsent | bearer | 254 |
| PUT | `/v1/privacy/consents` | updatePrivacyConsent | bearer | 255 |

## `messages`

| Method | Path | Handler | Auth | Baris |
|---|---|---|---|---:|
| GET | `/v1/messages` | listMessages | bearer | 256 |
| POST | `/v1/messages` | sendMessage | bearer | 257 |

## `notifications`

| Method | Path | Handler | Auth | Baris |
|---|---|---|---|---:|
| GET | `/v1/notifications` | listNotifications | bearer | 258 |
| PATCH | `/v1/notifications/read-all` | markAllNotificationsRead | bearer | 259 |
| PATCH | `/v1/notifications/{notification_id}/read` | markNotificationRead | bearer | 260 |
| POST | `/v1/notifications/test` | testNotification | bearer | 261 |

## `realtime`

| Method | Path | Handler | Auth | Baris |
|---|---|---|---|---:|
| GET | `/v1/realtime/ws` | realtimeWS | bearer (query token) | 262 |

## `emergency-contacts`

| Method | Path | Handler | Auth | Baris |
|---|---|---|---|---:|
| GET | `/v1/emergency-contacts` | listEmergencyContacts | bearer | 264 |
| POST | `/v1/emergency-contacts` | createEmergencyContact | bearer | 265 |
| PUT | `/v1/emergency-contacts/{id}` | updateEmergencyContact | bearer | 266 |
| DELETE | `/v1/emergency-contacts/{id}` | deleteEmergencyContact | bearer | 267 |

## `crisis-alerts`

| Method | Path | Handler | Auth | Baris |
|---|---|---|---|---:|
| POST | `/v1/crisis-alerts` | handleCrisisAlertV2 | bearer | 268 |

## `crisis-incidents`

| Method | Path | Handler | Auth | Baris |
|---|---|---|---|---:|
| GET | `/v1/crisis-incidents` | listCrisisIncidents | bearer | 269 |
| POST | `/v1/crisis-incidents/{id}/resolve` | resolveCrisisIncident | bearer | 270 |

## `sos-blast-status`

| Method | Path | Handler | Auth | Baris |
|---|---|---|---|---:|
| GET | `/v1/sos-blast-status` | listBlastStatus | bearer | 271 |

## `credentials`

| Method | Path | Handler | Auth | Baris |
|---|---|---|---|---:|
| POST | `/v1/credentials` | uploadCredentials | bearer | 273 |
| GET | `/v1/credentials/me` | getMyCredentials | bearer | 274 |

## `upload`

| Method | Path | Handler | Auth | Baris |
|---|---|---|---|---:|
| POST | `/v1/upload` | uploadFile | bearer | 276 |

## `uploads`

| Method | Path | Handler | Auth | Baris |
|---|---|---|---|---:|
| GET | `/uploads/` | uploads (statis) | publik | 278 |

## `psych-tests`

| Method | Path | Handler | Auth | Baris |
|---|---|---|---|---:|
| GET | `/v1/psych-tests` | listPsychTests | publik | 280 |

## `doctors`

| Method | Path | Handler | Auth | Baris |
|---|---|---|---|---:|
| GET | `/v1/doctors/search` | searchDoctors | publik | 283 |
| GET | `/v1/doctors/{user_id}` | getDoctorProfile | publik | 284 |
| GET | `/v1/doctors/{user_id}/slots` | getDoctorAvailableSlots | publik | 285 |
| GET | `/v1/doctors/{user_id}/availability` | getDoctorAvailability | publik | 286 |
| GET | `/v1/doctors/{user_id}/reviews` | listDoctorReviews | publik | 334 |
| POST | `/v1/doctors/{user_id}/reviews` | createDoctorReview | bearer | 335 |

## `pricing`

| Method | Path | Handler | Auth | Baris |
|---|---|---|---|---:|
| GET | `/v1/pricing` | getPricing | bearer | 287 |

## `bookings`

| Method | Path | Handler | Auth | Baris |
|---|---|---|---|---:|
| POST | `/v1/bookings` | createBooking | bearer | 289 |
| POST | `/v1/bookings/{booking_id}/cancel` | cancelPendingBooking | bearer | 290 |
| GET | `/v1/bookings` | listBookings | bearer | 299 |

## `payments`

| Method | Path | Handler | Auth | Baris |
|---|---|---|---|---:|
| POST | `/v1/payments` | createPayment | bearer | 291 |
| POST | `/v1/payments/mark-paid` | markPaymentPaid | bearer | 292 |
| GET | `/v1/payments/{reference}` | getPaymentStatus | bearer | 294 |

## `config`

| Method | Path | Handler | Auth | Baris |
|---|---|---|---|---:|
| GET | `/v1/config/payment` | paymentConfigHandler | publik | 296 |

## `webhooks`

| Method | Path | Handler | Auth | Baris |
|---|---|---|---|---:|
| POST | `/v1/webhooks/payment` | paymentWebhook | signature | 298 |

## `care-packages`

| Method | Path | Handler | Auth | Baris |
|---|---|---|---|---:|
| POST | `/v1/care-packages` | createCarePackage | bearer | 301 |
| GET | `/v1/care-packages` | listCarePackages | bearer | 302 |
| POST | `/v1/care-packages/{package_id}/cancel` | cancelPendingCarePackage | bearer | 303 |

## `care-sessions`

| Method | Path | Handler | Auth | Baris |
|---|---|---|---|---:|
| POST | `/v1/care-sessions` | scheduleSession | bearer | 304 |
| GET | `/v1/care-sessions` | listCareSessions | bearer | 305 |
| PATCH | `/v1/care-sessions/{session_id}` | updateCareSession | bearer | 306 |
| POST | `/v1/care-sessions/{session_id}/reschedule` | rescheduleCareSession | bearer | 307 |
| POST | `/v1/care-sessions/{session_id}/meet-link` | ensureMeetLinkHandler | bearer | 309 |
| PUT | `/v1/care-sessions/{session_id}/meet-link` | setManualMeetLinkHandler | bearer | 312 |
| POST | `/v1/care-sessions/{session_id}/refund` | refundCareSession | bearer | 322 |

## `google`

| Method | Path | Handler | Auth | Baris |
|---|---|---|---|---:|
| GET | `/v1/google/status` | googleStatusHandler | bearer | 314 |

## `professionals`

| Method | Path | Handler | Auth | Baris |
|---|---|---|---|---:|
| GET | `/v1/professionals/{professional_id}/meet-status` | meetStatusHandler | bearer | 318 |

## `meet`

| Method | Path | Handler | Auth | Baris |
|---|---|---|---|---:|
| POST | `/v1/meet/quick` | createQuickMeet | bearer | 320 |

## `care-refunds`

| Method | Path | Handler | Auth | Baris |
|---|---|---|---|---:|
| GET | `/v1/care-refunds` | listCareRefunds | bearer | 323 |

## `chat-permission`

| Method | Path | Handler | Auth | Baris |
|---|---|---|---|---:|
| GET | `/v1/chat-permission` | chatPermission | bearer | 324 |

## `professional`

| Method | Path | Handler | Auth | Baris |
|---|---|---|---|---:|
| GET | `/v1/professional/time-off` | listTimeOff | bearer | 326 |
| POST | `/v1/professional/time-off` | addTimeOff | bearer | 327 |
| DELETE | `/v1/professional/time-off/{id}` | deleteTimeOff | bearer | 328 |
| PUT | `/v1/professional/pricing` | updatePricing | bearer | 329 |
| GET | `/v1/professional/schedules` | listMySchedules | bearer | 330 |
| PUT | `/v1/professional/schedules` | updateMySchedules | bearer | 331 |
| DELETE | `/v1/professional/schedules/{id}` | deleteMySchedule | bearer | 333 |

## `earnings`

| Method | Path | Handler | Auth | Baris |
|---|---|---|---|---:|
| GET | `/v1/earnings` | earningsSummary | bearer | 336 |
| POST | `/v1/earnings/payout` | requestPayoutAll | bearer | 338 |
| POST | `/v1/earnings/{earning_id}/payout` | requestPayout | bearer | 339 |

## `e-prescriptions`

| Method | Path | Handler | Auth | Baris |
|---|---|---|---|---:|
| POST | `/v1/e-prescriptions` | createEPrescription | bearer | 340 |
| GET | `/v1/e-prescriptions` | listEPrescriptions | bearer | 341 |
| GET | `/v1/e-prescriptions/{id}` | getEPrescription | bearer | 342 |
| GET | `/v1/e-prescriptions/verify` | verifyEPrescriptionQR | publik | 344 |

## `health-record`

| Method | Path | Handler | Auth | Baris |
|---|---|---|---|---:|
| GET | `/v1/health-record` | getHealthRecord | bearer | 346 |
| PUT | `/v1/health-record` | updateHealthRecord | bearer | 347 |

## `goals`

| Method | Path | Handler | Auth | Baris |
|---|---|---|---|---:|
| GET | `/v1/goals` | listGoals | bearer | 349 |
| POST | `/v1/goals` | createGoal | bearer | 350 |
| PATCH | `/v1/goals/{goal_id}` | updateGoal | bearer | 351 |
| DELETE | `/v1/goals/{goal_id}` | deleteGoal | bearer | 352 |

## `habit-logs`

| Method | Path | Handler | Auth | Baris |
|---|---|---|---|---:|
| GET | `/v1/habit-logs` | listHabitLogs | bearer | 353 |
| POST | `/v1/habit-logs` | logHabit | bearer | 354 |

## `therapy-submissions`

| Method | Path | Handler | Auth | Baris |
|---|---|---|---|---:|
| GET | `/v1/therapy-submissions` | listTherapySubmissions | bearer | 356 |
| POST | `/v1/therapy-submissions` | createTherapySubmission | bearer | 357 |
| GET | `/v1/therapy-submissions/{submission_id}` | getTherapySubmission | bearer | 358 |
| POST | `/v1/therapy-submissions/{submission_id}/share` | shareTherapySubmission | bearer | 359 |
| DELETE | `/v1/therapy-submissions/{submission_id}` | deleteTherapySubmission | bearer | 360 |

## `admin`

| Method | Path | Handler | Auth | Baris |
|---|---|---|---|---:|
| GET | `/v1/admin/users` | listAdminUsers | bearer (admin) | 362 |
| PATCH | `/v1/admin/users/{user_id}` | updateAdminUser | bearer (admin) | 363 |
| DELETE | `/v1/admin/users/{user_id}` | deleteAdminUser | bearer (admin) | 364 |
| GET | `/v1/admin/credentials/pending` | listPendingCredentials | bearer (admin) | 365 |
| POST | `/v1/admin/credentials/{id}/verify` | verifyCredential | bearer (admin) | 366 |
| POST | `/v1/admin/doctors` | createAdminDoctor | bearer (admin) | 367 |
| GET | `/v1/admin/doctors` | listAdminDoctors | bearer (admin) | 368 |
| GET | `/v1/admin/doctors/{user_id}` | getAdminDoctor | bearer (admin) | 369 |
| PUT | `/v1/admin/doctors/{user_id}` | updateAdminDoctor | bearer (admin) | 370 |

