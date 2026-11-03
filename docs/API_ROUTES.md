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
| GET | `/` | root | publik | 215 |
| GET | `/healthz` | health | publik | 216 |

## `auth`

| Method | Path | Handler | Auth | Baris |
|---|---|---|---|---:|
| POST | `/v1/auth/register` | register | publik | 217 |
| POST | `/v1/auth/login` | login | publik | 218 |
| POST | `/v1/auth/google` | googleLogin | publik | 219 |
| POST | `/v1/auth/link-google` | linkGoogle | bearer | 220 |
| POST | `/v1/auth/bind-google` | bindGoogle | bearer | 221 |
| POST | `/v1/auth/unbind-google` | unbindGoogle | bearer | 222 |
| GET | `/v1/auth/google-identity` | googleIdentityStatus | bearer | 223 |
| POST | `/v1/auth/google-token-exchange` | exchangeGoogleToken | bearer | 224 |
| POST | `/v1/auth/complete-professional` | completeProfessionalProfile | bearer | 225 |
| POST | `/v1/auth/refresh` | refresh | publik | 226 |
| POST | `/v1/auth/logout` | logout | publik | 227 |
| POST | `/v1/auth/change-password` | changePassword | bearer | 228 |

## `me`

| Method | Path | Handler | Auth | Baris |
|---|---|---|---|---:|
| GET | `/v1/me` | me | bearer | 229 |
| PATCH | `/v1/me` | updateMe | bearer | 230 |

## `device-tokens`

| Method | Path | Handler | Auth | Baris |
|---|---|---|---|---:|
| POST | `/v1/device-tokens` | upsertDeviceToken | bearer | 231 |

## `screenings`

| Method | Path | Handler | Auth | Baris |
|---|---|---|---|---:|
| POST | `/v1/screenings` | createScreening | bearer | 232 |
| GET | `/v1/screenings` | listScreenings | bearer | 233 |
| POST | `/v1/screenings/{screening_id}/review` | reviewScreening | bearer | 234 |

## `screening-reviews`

| Method | Path | Handler | Auth | Baris |
|---|---|---|---|---:|
| GET | `/v1/screening-reviews` | listScreeningReviews | bearer | 235 |

## `patient-professional-links`

| Method | Path | Handler | Auth | Baris |
|---|---|---|---|---:|
| GET | `/v1/patient-professional-links` | listPatientProfessionalLinks | bearer | 236 |
| POST | `/v1/patient-professional-links` | linkPatientToProfessional | bearer | 237 |

## `professional-notes`

| Method | Path | Handler | Auth | Baris |
|---|---|---|---|---:|
| GET | `/v1/professional-notes` | listProfessionalNotes | bearer | 238 |
| POST | `/v1/professional-notes` | createProfessionalNote | bearer | 239 |

## `follow-ups`

| Method | Path | Handler | Auth | Baris |
|---|---|---|---|---:|
| GET | `/v1/follow-ups` | listFollowUps | bearer | 240 |
| POST | `/v1/follow-ups` | createFollowUp | bearer | 241 |
| PATCH | `/v1/follow-ups/{follow_up_id}/read` | markFollowUpRead | bearer | 242 |

## `mood-checkins`

| Method | Path | Handler | Auth | Baris |
|---|---|---|---|---:|
| GET | `/v1/mood-checkins` | listMoodCheckins | bearer | 243 |
| POST | `/v1/mood-checkins` | createMoodCheckin | bearer | 244 |

## `diary-entries`

| Method | Path | Handler | Auth | Baris |
|---|---|---|---|---:|
| GET | `/v1/diary-entries` | listDiaryEntries | bearer | 245 |
| POST | `/v1/diary-entries` | createDiaryEntry | bearer | 246 |
| PUT | `/v1/diary-entries/{diary_id}` | updateDiaryEntry | bearer | 247 |
| DELETE | `/v1/diary-entries/{diary_id}` | deleteDiaryEntry | bearer | 248 |
| PATCH | `/v1/diary-entries/{diary_id}/feedback` | updateDiaryFeedback | bearer | 249 |

## `medications`

| Method | Path | Handler | Auth | Baris |
|---|---|---|---|---:|
| GET | `/v1/medications` | listMedications | bearer | 250 |
| POST | `/v1/medications` | createMedication | bearer | 251 |
| PUT | `/v1/medications/{medication_id}` | updateMedication | bearer | 255 |
| DELETE | `/v1/medications/{medication_id}` | deleteMedication | bearer | 256 |

## `medication-logs`

| Method | Path | Handler | Auth | Baris |
|---|---|---|---|---:|
| GET | `/v1/medication-logs` | listMedicationLogs | bearer | 257 |
| POST | `/v1/medication-logs` | createMedicationLog | bearer | 258 |

## `timeline`

| Method | Path | Handler | Auth | Baris |
|---|---|---|---|---:|
| GET | `/v1/timeline` | timeline | bearer | 259 |

## `audit-logs`

| Method | Path | Handler | Auth | Baris |
|---|---|---|---|---:|
| GET | `/v1/audit-logs` | auditLogs | bearer | 260 |

## `privacy`

| Method | Path | Handler | Auth | Baris |
|---|---|---|---|---:|
| GET | `/v1/privacy/consents` | getPrivacyConsent | bearer | 261 |
| PUT | `/v1/privacy/consents` | updatePrivacyConsent | bearer | 262 |

## `messages`

| Method | Path | Handler | Auth | Baris |
|---|---|---|---|---:|
| GET | `/v1/messages` | listMessages | bearer | 263 |
| POST | `/v1/messages` | sendMessage | bearer | 264 |

## `notifications`

| Method | Path | Handler | Auth | Baris |
|---|---|---|---|---:|
| GET | `/v1/notifications` | listNotifications | bearer | 265 |
| PATCH | `/v1/notifications/read-all` | markAllNotificationsRead | bearer | 266 |
| PATCH | `/v1/notifications/{notification_id}/read` | markNotificationRead | bearer | 267 |
| POST | `/v1/notifications/test` | testNotification | bearer | 268 |

## `realtime`

| Method | Path | Handler | Auth | Baris |
|---|---|---|---|---:|
| GET | `/v1/realtime/ws` | realtimeWS | bearer (query token) | 269 |

## `emergency-contacts`

| Method | Path | Handler | Auth | Baris |
|---|---|---|---|---:|
| GET | `/v1/emergency-contacts` | listEmergencyContacts | bearer | 271 |
| POST | `/v1/emergency-contacts` | createEmergencyContact | bearer | 272 |
| PUT | `/v1/emergency-contacts/{id}` | updateEmergencyContact | bearer | 273 |
| DELETE | `/v1/emergency-contacts/{id}` | deleteEmergencyContact | bearer | 274 |

## `crisis-alerts`

| Method | Path | Handler | Auth | Baris |
|---|---|---|---|---:|
| POST | `/v1/crisis-alerts` | handleCrisisAlertV2 | bearer | 275 |

## `crisis-incidents`

| Method | Path | Handler | Auth | Baris |
|---|---|---|---|---:|
| GET | `/v1/crisis-incidents` | listCrisisIncidents | bearer | 276 |
| POST | `/v1/crisis-incidents/{id}/resolve` | resolveCrisisIncident | bearer | 277 |

## `crisis-incident-log`

| Method | Path | Handler | Auth | Baris |
|---|---|---|---|---:|
| GET | `/v1/crisis-incident-log` | listCrisisIncidentLog | bearer | 278 |

## `sos-blast-status`

| Method | Path | Handler | Auth | Baris |
|---|---|---|---|---:|
| GET | `/v1/sos-blast-status` | listBlastStatus | bearer | 279 |

## `credentials`

| Method | Path | Handler | Auth | Baris |
|---|---|---|---|---:|
| POST | `/v1/credentials` | uploadCredentials | bearer | 281 |
| GET | `/v1/credentials/me` | getMyCredentials | bearer | 282 |

## `upload`

| Method | Path | Handler | Auth | Baris |
|---|---|---|---|---:|
| POST | `/v1/upload` | uploadFile | bearer | 284 |

## `uploads`

| Method | Path | Handler | Auth | Baris |
|---|---|---|---|---:|
| GET | `/uploads/` | uploads (statis) | publik | 286 |

## `psych-tests`

| Method | Path | Handler | Auth | Baris |
|---|---|---|---|---:|
| GET | `/v1/psych-tests` | listPsychTests | publik | 288 |

## `doctors`

| Method | Path | Handler | Auth | Baris |
|---|---|---|---|---:|
| GET | `/v1/doctors/search` | searchDoctors | publik | 291 |
| GET | `/v1/doctors/{user_id}` | getDoctorProfile | publik | 292 |
| GET | `/v1/doctors/{user_id}/slots` | getDoctorAvailableSlots | publik | 293 |
| GET | `/v1/doctors/{user_id}/availability` | getDoctorAvailability | publik | 294 |
| GET | `/v1/doctors/{user_id}/reviews` | listDoctorReviews | publik | 342 |
| POST | `/v1/doctors/{user_id}/reviews` | createDoctorReview | bearer | 343 |

## `pricing`

| Method | Path | Handler | Auth | Baris |
|---|---|---|---|---:|
| GET | `/v1/pricing` | getPricing | bearer | 295 |

## `bookings`

| Method | Path | Handler | Auth | Baris |
|---|---|---|---|---:|
| POST | `/v1/bookings` | createBooking | bearer | 297 |
| POST | `/v1/bookings/{booking_id}/cancel` | cancelPendingBooking | bearer | 298 |
| GET | `/v1/bookings` | listBookings | bearer | 307 |

## `payments`

| Method | Path | Handler | Auth | Baris |
|---|---|---|---|---:|
| POST | `/v1/payments` | createPayment | bearer | 299 |
| POST | `/v1/payments/mark-paid` | markPaymentPaid | bearer | 300 |
| GET | `/v1/payments/{reference}` | getPaymentStatus | bearer | 302 |

## `config`

| Method | Path | Handler | Auth | Baris |
|---|---|---|---|---:|
| GET | `/v1/config/payment` | paymentConfigHandler | publik | 304 |

## `webhooks`

| Method | Path | Handler | Auth | Baris |
|---|---|---|---|---:|
| POST | `/v1/webhooks/payment` | paymentWebhook | signature | 306 |

## `care-packages`

| Method | Path | Handler | Auth | Baris |
|---|---|---|---|---:|
| POST | `/v1/care-packages` | createCarePackage | bearer | 309 |
| GET | `/v1/care-packages` | listCarePackages | bearer | 310 |
| POST | `/v1/care-packages/{package_id}/cancel` | cancelPendingCarePackage | bearer | 311 |

## `care-sessions`

| Method | Path | Handler | Auth | Baris |
|---|---|---|---|---:|
| POST | `/v1/care-sessions` | scheduleSession | bearer | 312 |
| GET | `/v1/care-sessions` | listCareSessions | bearer | 313 |
| PATCH | `/v1/care-sessions/{session_id}` | updateCareSession | bearer | 314 |
| POST | `/v1/care-sessions/{session_id}/reschedule` | rescheduleCareSession | bearer | 315 |
| POST | `/v1/care-sessions/{session_id}/meet-link` | ensureMeetLinkHandler | bearer | 317 |
| PUT | `/v1/care-sessions/{session_id}/meet-link` | setManualMeetLinkHandler | bearer | 320 |
| POST | `/v1/care-sessions/{session_id}/refund` | refundCareSession | bearer | 330 |

## `google`

| Method | Path | Handler | Auth | Baris |
|---|---|---|---|---:|
| GET | `/v1/google/status` | googleStatusHandler | bearer | 322 |

## `professionals`

| Method | Path | Handler | Auth | Baris |
|---|---|---|---|---:|
| GET | `/v1/professionals/{professional_id}/meet-status` | meetStatusHandler | bearer | 326 |

## `meet`

| Method | Path | Handler | Auth | Baris |
|---|---|---|---|---:|
| POST | `/v1/meet/quick` | createQuickMeet | bearer | 328 |

## `care-refunds`

| Method | Path | Handler | Auth | Baris |
|---|---|---|---|---:|
| GET | `/v1/care-refunds` | listCareRefunds | bearer | 331 |

## `chat-permission`

| Method | Path | Handler | Auth | Baris |
|---|---|---|---|---:|
| GET | `/v1/chat-permission` | chatPermission | bearer | 332 |

## `professional`

| Method | Path | Handler | Auth | Baris |
|---|---|---|---|---:|
| GET | `/v1/professional/time-off` | listTimeOff | bearer | 334 |
| POST | `/v1/professional/time-off` | addTimeOff | bearer | 335 |
| DELETE | `/v1/professional/time-off/{id}` | deleteTimeOff | bearer | 336 |
| PUT | `/v1/professional/pricing` | updatePricing | bearer | 337 |
| GET | `/v1/professional/schedules` | listMySchedules | bearer | 338 |
| PUT | `/v1/professional/schedules` | updateMySchedules | bearer | 339 |
| DELETE | `/v1/professional/schedules/{id}` | deleteMySchedule | bearer | 341 |

## `earnings`

| Method | Path | Handler | Auth | Baris |
|---|---|---|---|---:|
| GET | `/v1/earnings` | earningsSummary | bearer | 344 |
| POST | `/v1/earnings/payout` | requestPayoutAll | bearer | 346 |
| POST | `/v1/earnings/{earning_id}/payout` | requestPayout | bearer | 347 |

## `e-prescriptions`

| Method | Path | Handler | Auth | Baris |
|---|---|---|---|---:|
| POST | `/v1/e-prescriptions` | createEPrescription | bearer | 348 |
| GET | `/v1/e-prescriptions` | listEPrescriptions | bearer | 349 |
| GET | `/v1/e-prescriptions/{id}` | getEPrescription | bearer | 350 |
| GET | `/v1/e-prescriptions/verify` | verifyEPrescriptionQR | publik | 352 |

## `health-record`

| Method | Path | Handler | Auth | Baris |
|---|---|---|---|---:|
| GET | `/v1/health-record` | getHealthRecord | bearer | 354 |
| PUT | `/v1/health-record` | updateHealthRecord | bearer | 355 |

## `goals`

| Method | Path | Handler | Auth | Baris |
|---|---|---|---|---:|
| GET | `/v1/goals` | listGoals | bearer | 357 |
| POST | `/v1/goals` | createGoal | bearer | 358 |
| PATCH | `/v1/goals/{goal_id}` | updateGoal | bearer | 359 |
| DELETE | `/v1/goals/{goal_id}` | deleteGoal | bearer | 360 |

## `habit-logs`

| Method | Path | Handler | Auth | Baris |
|---|---|---|---|---:|
| GET | `/v1/habit-logs` | listHabitLogs | bearer | 361 |
| POST | `/v1/habit-logs` | logHabit | bearer | 362 |

## `therapy-submissions`

| Method | Path | Handler | Auth | Baris |
|---|---|---|---|---:|
| GET | `/v1/therapy-submissions` | listTherapySubmissions | bearer | 364 |
| POST | `/v1/therapy-submissions` | createTherapySubmission | bearer | 365 |
| GET | `/v1/therapy-submissions/{submission_id}` | getTherapySubmission | bearer | 366 |
| POST | `/v1/therapy-submissions/{submission_id}/share` | shareTherapySubmission | bearer | 367 |
| DELETE | `/v1/therapy-submissions/{submission_id}` | deleteTherapySubmission | bearer | 368 |

## `admin`

| Method | Path | Handler | Auth | Baris |
|---|---|---|---|---:|
| GET | `/v1/admin/users` | listAdminUsers | bearer (admin) | 370 |
| PATCH | `/v1/admin/users/{user_id}` | updateAdminUser | bearer (admin) | 371 |
| DELETE | `/v1/admin/users/{user_id}` | deleteAdminUser | bearer (admin) | 372 |
| GET | `/v1/admin/credentials/pending` | listPendingCredentials | bearer (admin) | 373 |
| POST | `/v1/admin/credentials/{id}/verify` | verifyCredential | bearer (admin) | 374 |
| POST | `/v1/admin/doctors` | createAdminDoctor | bearer (admin) | 375 |
| GET | `/v1/admin/doctors` | listAdminDoctors | bearer (admin) | 376 |
| GET | `/v1/admin/doctors/{user_id}` | getAdminDoctor | bearer (admin) | 377 |
| PUT | `/v1/admin/doctors/{user_id}` | updateAdminDoctor | bearer (admin) | 378 |
| GET | `/v1/admin/overview` | adminOverview | bearer (admin) | 383 |
| GET | `/v1/admin/payments` | listAdminPayments | bearer (admin) | 384 |
| GET | `/v1/admin/payments/{payment_id}` | getAdminPayment | bearer (admin) | 385 |
| POST | `/v1/admin/payments/{payment_id}/override` | overrideAdminPayment | bearer (admin) | 386 |
| GET | `/v1/admin/pricing` | listAdminPricing | bearer (admin) | 387 |
| PUT | `/v1/admin/pricing/{professional_id}` | updateAdminPricing | bearer (admin) | 388 |
| GET | `/v1/admin/refunds` | listAdminRefunds | bearer (admin) | 389 |
| POST | `/v1/admin/users/{user_id}/reset-password` | resetAdminUserPassword | bearer (admin) | 390 |
| POST | `/v1/admin/users/{user_id}/revoke-sessions` | revokeAdminUserSessions | bearer (admin) | 391 |

