# Inventaris Rute API Malva

> **Dibuat otomatis oleh `go run ./cmd/apidoc` — jangan diedit manual.**
> Sumber kebenaran: `backend/internal/server/server.go` (fungsi `Routes()`).
> Regenerasi: `cd backend && go run ./cmd/apidoc`
> Verifikasi sinkron: `cd backend && go run ./cmd/apidoc -check`

Total endpoint API: **140** (+1 penyajian berkas statis `GET /uploads/`).

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
| crisis-incident-log | 1 |
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
| admin | 18 |

## `system`

| Method | Path | Handler | Auth | Baris |
|---|---|---|---|---:|
| GET | `/` | root | publik | 210 |
| GET | `/healthz` | health | publik | 211 |

## `auth`

| Method | Path | Handler | Auth | Baris |
|---|---|---|---|---:|
| POST | `/v1/auth/register` | register | publik | 212 |
| POST | `/v1/auth/login` | login | publik | 213 |
| POST | `/v1/auth/google` | googleLogin | publik | 214 |
| POST | `/v1/auth/link-google` | linkGoogle | bearer | 215 |
| POST | `/v1/auth/bind-google` | bindGoogle | bearer | 216 |
| POST | `/v1/auth/unbind-google` | unbindGoogle | bearer | 217 |
| GET | `/v1/auth/google-identity` | googleIdentityStatus | bearer | 218 |
| POST | `/v1/auth/google-token-exchange` | exchangeGoogleToken | bearer | 219 |
| POST | `/v1/auth/complete-professional` | completeProfessionalProfile | bearer | 220 |
| POST | `/v1/auth/refresh` | refresh | publik | 221 |
| POST | `/v1/auth/logout` | logout | publik | 222 |
| POST | `/v1/auth/change-password` | changePassword | bearer | 223 |

## `me`

| Method | Path | Handler | Auth | Baris |
|---|---|---|---|---:|
| GET | `/v1/me` | me | bearer | 224 |
| PATCH | `/v1/me` | updateMe | bearer | 225 |

## `device-tokens`

| Method | Path | Handler | Auth | Baris |
|---|---|---|---|---:|
| POST | `/v1/device-tokens` | upsertDeviceToken | bearer | 226 |

## `screenings`

| Method | Path | Handler | Auth | Baris |
|---|---|---|---|---:|
| POST | `/v1/screenings` | createScreening | bearer | 227 |
| GET | `/v1/screenings` | listScreenings | bearer | 228 |
| POST | `/v1/screenings/{screening_id}/review` | reviewScreening | bearer | 229 |

## `screening-reviews`

| Method | Path | Handler | Auth | Baris |
|---|---|---|---|---:|
| GET | `/v1/screening-reviews` | listScreeningReviews | bearer | 230 |

## `patient-professional-links`

| Method | Path | Handler | Auth | Baris |
|---|---|---|---|---:|
| GET | `/v1/patient-professional-links` | listPatientProfessionalLinks | bearer | 231 |
| POST | `/v1/patient-professional-links` | linkPatientToProfessional | bearer | 232 |

## `professional-notes`

| Method | Path | Handler | Auth | Baris |
|---|---|---|---|---:|
| GET | `/v1/professional-notes` | listProfessionalNotes | bearer | 233 |
| POST | `/v1/professional-notes` | createProfessionalNote | bearer | 234 |

## `follow-ups`

| Method | Path | Handler | Auth | Baris |
|---|---|---|---|---:|
| GET | `/v1/follow-ups` | listFollowUps | bearer | 235 |
| POST | `/v1/follow-ups` | createFollowUp | bearer | 236 |
| PATCH | `/v1/follow-ups/{follow_up_id}/read` | markFollowUpRead | bearer | 237 |

## `mood-checkins`

| Method | Path | Handler | Auth | Baris |
|---|---|---|---|---:|
| GET | `/v1/mood-checkins` | listMoodCheckins | bearer | 238 |
| POST | `/v1/mood-checkins` | createMoodCheckin | bearer | 239 |

## `diary-entries`

| Method | Path | Handler | Auth | Baris |
|---|---|---|---|---:|
| GET | `/v1/diary-entries` | listDiaryEntries | bearer | 240 |
| POST | `/v1/diary-entries` | createDiaryEntry | bearer | 241 |
| PUT | `/v1/diary-entries/{diary_id}` | updateDiaryEntry | bearer | 242 |
| DELETE | `/v1/diary-entries/{diary_id}` | deleteDiaryEntry | bearer | 243 |
| PATCH | `/v1/diary-entries/{diary_id}/feedback` | updateDiaryFeedback | bearer | 244 |

## `medications`

| Method | Path | Handler | Auth | Baris |
|---|---|---|---|---:|
| GET | `/v1/medications` | listMedications | bearer | 245 |
| POST | `/v1/medications` | createMedication | bearer | 246 |
| PUT | `/v1/medications/{medication_id}` | updateMedication | bearer | 250 |
| DELETE | `/v1/medications/{medication_id}` | deleteMedication | bearer | 251 |

## `medication-logs`

| Method | Path | Handler | Auth | Baris |
|---|---|---|---|---:|
| GET | `/v1/medication-logs` | listMedicationLogs | bearer | 252 |
| POST | `/v1/medication-logs` | createMedicationLog | bearer | 253 |

## `timeline`

| Method | Path | Handler | Auth | Baris |
|---|---|---|---|---:|
| GET | `/v1/timeline` | timeline | bearer | 254 |

## `audit-logs`

| Method | Path | Handler | Auth | Baris |
|---|---|---|---|---:|
| GET | `/v1/audit-logs` | auditLogs | bearer | 255 |

## `privacy`

| Method | Path | Handler | Auth | Baris |
|---|---|---|---|---:|
| GET | `/v1/privacy/consents` | getPrivacyConsent | bearer | 256 |
| PUT | `/v1/privacy/consents` | updatePrivacyConsent | bearer | 257 |

## `messages`

| Method | Path | Handler | Auth | Baris |
|---|---|---|---|---:|
| GET | `/v1/messages` | listMessages | bearer | 258 |
| POST | `/v1/messages` | sendMessage | bearer | 259 |

## `notifications`

| Method | Path | Handler | Auth | Baris |
|---|---|---|---|---:|
| GET | `/v1/notifications` | listNotifications | bearer | 260 |
| PATCH | `/v1/notifications/read-all` | markAllNotificationsRead | bearer | 261 |
| PATCH | `/v1/notifications/{notification_id}/read` | markNotificationRead | bearer | 262 |
| POST | `/v1/notifications/test` | testNotification | bearer | 263 |

## `realtime`

| Method | Path | Handler | Auth | Baris |
|---|---|---|---|---:|
| GET | `/v1/realtime/ws` | realtimeWS | bearer (query token) | 264 |

## `emergency-contacts`

| Method | Path | Handler | Auth | Baris |
|---|---|---|---|---:|
| GET | `/v1/emergency-contacts` | listEmergencyContacts | bearer | 266 |
| POST | `/v1/emergency-contacts` | createEmergencyContact | bearer | 267 |
| PUT | `/v1/emergency-contacts/{id}` | updateEmergencyContact | bearer | 268 |
| DELETE | `/v1/emergency-contacts/{id}` | deleteEmergencyContact | bearer | 269 |

## `crisis-alerts`

| Method | Path | Handler | Auth | Baris |
|---|---|---|---|---:|
| POST | `/v1/crisis-alerts` | handleCrisisAlertV2 | bearer | 270 |

## `crisis-incidents`

| Method | Path | Handler | Auth | Baris |
|---|---|---|---|---:|
| GET | `/v1/crisis-incidents` | listCrisisIncidents | bearer | 271 |
| POST | `/v1/crisis-incidents/{id}/resolve` | resolveCrisisIncident | bearer | 272 |

## `crisis-incident-log`

| Method | Path | Handler | Auth | Baris |
|---|---|---|---|---:|
| GET | `/v1/crisis-incident-log` | listCrisisIncidentLog | bearer | 273 |

## `sos-blast-status`

| Method | Path | Handler | Auth | Baris |
|---|---|---|---|---:|
| GET | `/v1/sos-blast-status` | listBlastStatus | bearer | 274 |

## `credentials`

| Method | Path | Handler | Auth | Baris |
|---|---|---|---|---:|
| POST | `/v1/credentials` | uploadCredentials | bearer | 276 |
| GET | `/v1/credentials/me` | getMyCredentials | bearer | 277 |

## `upload`

| Method | Path | Handler | Auth | Baris |
|---|---|---|---|---:|
| POST | `/v1/upload` | uploadFile | bearer | 279 |

## `uploads`

| Method | Path | Handler | Auth | Baris |
|---|---|---|---|---:|
| GET | `/uploads/` | uploads (statis) | publik | 281 |

## `psych-tests`

| Method | Path | Handler | Auth | Baris |
|---|---|---|---|---:|
| GET | `/v1/psych-tests` | listPsychTests | publik | 283 |

## `doctors`

| Method | Path | Handler | Auth | Baris |
|---|---|---|---|---:|
| GET | `/v1/doctors/search` | searchDoctors | publik | 286 |
| GET | `/v1/doctors/{user_id}` | getDoctorProfile | publik | 287 |
| GET | `/v1/doctors/{user_id}/slots` | getDoctorAvailableSlots | publik | 288 |
| GET | `/v1/doctors/{user_id}/availability` | getDoctorAvailability | publik | 289 |
| GET | `/v1/doctors/{user_id}/reviews` | listDoctorReviews | publik | 337 |
| POST | `/v1/doctors/{user_id}/reviews` | createDoctorReview | bearer | 338 |

## `pricing`

| Method | Path | Handler | Auth | Baris |
|---|---|---|---|---:|
| GET | `/v1/pricing` | getPricing | bearer | 290 |

## `bookings`

| Method | Path | Handler | Auth | Baris |
|---|---|---|---|---:|
| POST | `/v1/bookings` | createBooking | bearer | 292 |
| POST | `/v1/bookings/{booking_id}/cancel` | cancelPendingBooking | bearer | 293 |
| GET | `/v1/bookings` | listBookings | bearer | 302 |

## `payments`

| Method | Path | Handler | Auth | Baris |
|---|---|---|---|---:|
| POST | `/v1/payments` | createPayment | bearer | 294 |
| POST | `/v1/payments/mark-paid` | markPaymentPaid | bearer | 295 |
| GET | `/v1/payments/{reference}` | getPaymentStatus | bearer | 297 |

## `config`

| Method | Path | Handler | Auth | Baris |
|---|---|---|---|---:|
| GET | `/v1/config/payment` | paymentConfigHandler | publik | 299 |

## `webhooks`

| Method | Path | Handler | Auth | Baris |
|---|---|---|---|---:|
| POST | `/v1/webhooks/payment` | paymentWebhook | signature | 301 |

## `care-packages`

| Method | Path | Handler | Auth | Baris |
|---|---|---|---|---:|
| POST | `/v1/care-packages` | createCarePackage | bearer | 304 |
| GET | `/v1/care-packages` | listCarePackages | bearer | 305 |
| POST | `/v1/care-packages/{package_id}/cancel` | cancelPendingCarePackage | bearer | 306 |

## `care-sessions`

| Method | Path | Handler | Auth | Baris |
|---|---|---|---|---:|
| POST | `/v1/care-sessions` | scheduleSession | bearer | 307 |
| GET | `/v1/care-sessions` | listCareSessions | bearer | 308 |
| PATCH | `/v1/care-sessions/{session_id}` | updateCareSession | bearer | 309 |
| POST | `/v1/care-sessions/{session_id}/reschedule` | rescheduleCareSession | bearer | 310 |
| POST | `/v1/care-sessions/{session_id}/meet-link` | ensureMeetLinkHandler | bearer | 312 |
| PUT | `/v1/care-sessions/{session_id}/meet-link` | setManualMeetLinkHandler | bearer | 315 |
| POST | `/v1/care-sessions/{session_id}/refund` | refundCareSession | bearer | 325 |

## `google`

| Method | Path | Handler | Auth | Baris |
|---|---|---|---|---:|
| GET | `/v1/google/status` | googleStatusHandler | bearer | 317 |

## `professionals`

| Method | Path | Handler | Auth | Baris |
|---|---|---|---|---:|
| GET | `/v1/professionals/{professional_id}/meet-status` | meetStatusHandler | bearer | 321 |

## `meet`

| Method | Path | Handler | Auth | Baris |
|---|---|---|---|---:|
| POST | `/v1/meet/quick` | createQuickMeet | bearer | 323 |

## `care-refunds`

| Method | Path | Handler | Auth | Baris |
|---|---|---|---|---:|
| GET | `/v1/care-refunds` | listCareRefunds | bearer | 326 |

## `chat-permission`

| Method | Path | Handler | Auth | Baris |
|---|---|---|---|---:|
| GET | `/v1/chat-permission` | chatPermission | bearer | 327 |

## `professional`

| Method | Path | Handler | Auth | Baris |
|---|---|---|---|---:|
| GET | `/v1/professional/time-off` | listTimeOff | bearer | 329 |
| POST | `/v1/professional/time-off` | addTimeOff | bearer | 330 |
| DELETE | `/v1/professional/time-off/{id}` | deleteTimeOff | bearer | 331 |
| PUT | `/v1/professional/pricing` | updatePricing | bearer | 332 |
| GET | `/v1/professional/schedules` | listMySchedules | bearer | 333 |
| PUT | `/v1/professional/schedules` | updateMySchedules | bearer | 334 |
| DELETE | `/v1/professional/schedules/{id}` | deleteMySchedule | bearer | 336 |

## `earnings`

| Method | Path | Handler | Auth | Baris |
|---|---|---|---|---:|
| GET | `/v1/earnings` | earningsSummary | bearer | 339 |
| POST | `/v1/earnings/payout` | requestPayoutAll | bearer | 341 |
| POST | `/v1/earnings/{earning_id}/payout` | requestPayout | bearer | 342 |

## `e-prescriptions`

| Method | Path | Handler | Auth | Baris |
|---|---|---|---|---:|
| POST | `/v1/e-prescriptions` | createEPrescription | bearer | 343 |
| GET | `/v1/e-prescriptions` | listEPrescriptions | bearer | 344 |
| GET | `/v1/e-prescriptions/{id}` | getEPrescription | bearer | 345 |
| GET | `/v1/e-prescriptions/verify` | verifyEPrescriptionQR | publik | 347 |

## `health-record`

| Method | Path | Handler | Auth | Baris |
|---|---|---|---|---:|
| GET | `/v1/health-record` | getHealthRecord | bearer | 349 |
| PUT | `/v1/health-record` | updateHealthRecord | bearer | 350 |

## `goals`

| Method | Path | Handler | Auth | Baris |
|---|---|---|---|---:|
| GET | `/v1/goals` | listGoals | bearer | 352 |
| POST | `/v1/goals` | createGoal | bearer | 353 |
| PATCH | `/v1/goals/{goal_id}` | updateGoal | bearer | 354 |
| DELETE | `/v1/goals/{goal_id}` | deleteGoal | bearer | 355 |

## `habit-logs`

| Method | Path | Handler | Auth | Baris |
|---|---|---|---|---:|
| GET | `/v1/habit-logs` | listHabitLogs | bearer | 356 |
| POST | `/v1/habit-logs` | logHabit | bearer | 357 |

## `therapy-submissions`

| Method | Path | Handler | Auth | Baris |
|---|---|---|---|---:|
| GET | `/v1/therapy-submissions` | listTherapySubmissions | bearer | 359 |
| POST | `/v1/therapy-submissions` | createTherapySubmission | bearer | 360 |
| GET | `/v1/therapy-submissions/{submission_id}` | getTherapySubmission | bearer | 361 |
| POST | `/v1/therapy-submissions/{submission_id}/share` | shareTherapySubmission | bearer | 362 |
| DELETE | `/v1/therapy-submissions/{submission_id}` | deleteTherapySubmission | bearer | 363 |

## `admin`

| Method | Path | Handler | Auth | Baris |
|---|---|---|---|---:|
| GET | `/v1/admin/users` | listAdminUsers | bearer (admin) | 365 |
| PATCH | `/v1/admin/users/{user_id}` | updateAdminUser | bearer (admin) | 366 |
| DELETE | `/v1/admin/users/{user_id}` | deleteAdminUser | bearer (admin) | 367 |
| GET | `/v1/admin/credentials/pending` | listPendingCredentials | bearer (admin) | 368 |
| POST | `/v1/admin/credentials/{id}/verify` | verifyCredential | bearer (admin) | 369 |
| POST | `/v1/admin/doctors` | createAdminDoctor | bearer (admin) | 370 |
| GET | `/v1/admin/doctors` | listAdminDoctors | bearer (admin) | 371 |
| GET | `/v1/admin/doctors/{user_id}` | getAdminDoctor | bearer (admin) | 372 |
| PUT | `/v1/admin/doctors/{user_id}` | updateAdminDoctor | bearer (admin) | 373 |
| GET | `/v1/admin/overview` | adminOverview | bearer (admin) | 378 |
| GET | `/v1/admin/payments` | listAdminPayments | bearer (admin) | 379 |
| GET | `/v1/admin/payments/{payment_id}` | getAdminPayment | bearer (admin) | 380 |
| POST | `/v1/admin/payments/{payment_id}/override` | overrideAdminPayment | bearer (admin) | 381 |
| GET | `/v1/admin/pricing` | listAdminPricing | bearer (admin) | 382 |
| PUT | `/v1/admin/pricing/{professional_id}` | updateAdminPricing | bearer (admin) | 383 |
| GET | `/v1/admin/refunds` | listAdminRefunds | bearer (admin) | 384 |
| POST | `/v1/admin/users/{user_id}/reset-password` | resetAdminUserPassword | bearer (admin) | 385 |
| POST | `/v1/admin/users/{user_id}/revoke-sessions` | revokeAdminUserSessions | bearer (admin) | 386 |

