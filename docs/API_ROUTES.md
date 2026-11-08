# Inventaris Rute API Malva

> **Dibuat otomatis oleh `go run ./cmd/apidoc` — jangan diedit manual.**
> Sumber kebenaran: `backend/internal/server/server.go` (fungsi `Routes()`).
> Regenerasi: `cd backend && go run ./cmd/apidoc`
> Verifikasi sinkron: `cd backend && go run ./cmd/apidoc -check`

Total endpoint API: **144** (+1 penyajian berkas statis `GET /uploads/`).

## Ringkasan per Tag

| Tag | Jumlah Endpoint |
|---|---:|
| system | 2 |
| auth | 12 |
| me | 2 |
| device-tokens | 2 |
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
| chat-attachments | 2 |
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
| review-entitlements | 1 |
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
| DELETE | `/v1/device-tokens` | deleteDeviceToken | bearer | 234 |

## `screenings`

| Method | Path | Handler | Auth | Baris |
|---|---|---|---|---:|
| POST | `/v1/screenings` | createScreening | bearer | 235 |
| GET | `/v1/screenings` | listScreenings | bearer | 236 |
| POST | `/v1/screenings/{screening_id}/review` | reviewScreening | bearer | 237 |

## `screening-reviews`

| Method | Path | Handler | Auth | Baris |
|---|---|---|---|---:|
| GET | `/v1/screening-reviews` | listScreeningReviews | bearer | 238 |

## `patient-professional-links`

| Method | Path | Handler | Auth | Baris |
|---|---|---|---|---:|
| GET | `/v1/patient-professional-links` | listPatientProfessionalLinks | bearer | 239 |
| POST | `/v1/patient-professional-links` | linkPatientToProfessional | bearer | 240 |

## `professional-notes`

| Method | Path | Handler | Auth | Baris |
|---|---|---|---|---:|
| GET | `/v1/professional-notes` | listProfessionalNotes | bearer | 241 |
| POST | `/v1/professional-notes` | createProfessionalNote | bearer | 242 |

## `follow-ups`

| Method | Path | Handler | Auth | Baris |
|---|---|---|---|---:|
| GET | `/v1/follow-ups` | listFollowUps | bearer | 243 |
| POST | `/v1/follow-ups` | createFollowUp | bearer | 244 |
| PATCH | `/v1/follow-ups/{follow_up_id}/read` | markFollowUpRead | bearer | 245 |

## `mood-checkins`

| Method | Path | Handler | Auth | Baris |
|---|---|---|---|---:|
| GET | `/v1/mood-checkins` | listMoodCheckins | bearer | 246 |
| POST | `/v1/mood-checkins` | createMoodCheckin | bearer | 247 |

## `diary-entries`

| Method | Path | Handler | Auth | Baris |
|---|---|---|---|---:|
| GET | `/v1/diary-entries` | listDiaryEntries | bearer | 248 |
| POST | `/v1/diary-entries` | createDiaryEntry | bearer | 249 |
| PUT | `/v1/diary-entries/{diary_id}` | updateDiaryEntry | bearer | 250 |
| DELETE | `/v1/diary-entries/{diary_id}` | deleteDiaryEntry | bearer | 251 |
| PATCH | `/v1/diary-entries/{diary_id}/feedback` | updateDiaryFeedback | bearer | 252 |

## `medications`

| Method | Path | Handler | Auth | Baris |
|---|---|---|---|---:|
| GET | `/v1/medications` | listMedications | bearer | 253 |
| POST | `/v1/medications` | createMedication | bearer | 254 |
| PUT | `/v1/medications/{medication_id}` | updateMedication | bearer | 258 |
| DELETE | `/v1/medications/{medication_id}` | deleteMedication | bearer | 259 |

## `medication-logs`

| Method | Path | Handler | Auth | Baris |
|---|---|---|---|---:|
| GET | `/v1/medication-logs` | listMedicationLogs | bearer | 260 |
| POST | `/v1/medication-logs` | createMedicationLog | bearer | 261 |

## `timeline`

| Method | Path | Handler | Auth | Baris |
|---|---|---|---|---:|
| GET | `/v1/timeline` | timeline | bearer | 262 |

## `audit-logs`

| Method | Path | Handler | Auth | Baris |
|---|---|---|---|---:|
| GET | `/v1/audit-logs` | auditLogs | bearer | 263 |

## `privacy`

| Method | Path | Handler | Auth | Baris |
|---|---|---|---|---:|
| GET | `/v1/privacy/consents` | getPrivacyConsent | bearer | 264 |
| PUT | `/v1/privacy/consents` | updatePrivacyConsent | bearer | 265 |

## `messages`

| Method | Path | Handler | Auth | Baris |
|---|---|---|---|---:|
| GET | `/v1/messages` | listMessages | bearer | 266 |
| POST | `/v1/messages` | sendMessage | bearer | 267 |

## `notifications`

| Method | Path | Handler | Auth | Baris |
|---|---|---|---|---:|
| GET | `/v1/notifications` | listNotifications | bearer | 268 |
| PATCH | `/v1/notifications/read-all` | markAllNotificationsRead | bearer | 269 |
| PATCH | `/v1/notifications/{notification_id}/read` | markNotificationRead | bearer | 270 |
| POST | `/v1/notifications/test` | testNotification | bearer | 271 |

## `realtime`

| Method | Path | Handler | Auth | Baris |
|---|---|---|---|---:|
| GET | `/v1/realtime/ws` | realtimeWS | bearer (query token) | 272 |

## `emergency-contacts`

| Method | Path | Handler | Auth | Baris |
|---|---|---|---|---:|
| GET | `/v1/emergency-contacts` | listEmergencyContacts | bearer | 274 |
| POST | `/v1/emergency-contacts` | createEmergencyContact | bearer | 275 |
| PUT | `/v1/emergency-contacts/{id}` | updateEmergencyContact | bearer | 276 |
| DELETE | `/v1/emergency-contacts/{id}` | deleteEmergencyContact | bearer | 277 |

## `crisis-alerts`

| Method | Path | Handler | Auth | Baris |
|---|---|---|---|---:|
| POST | `/v1/crisis-alerts` | handleCrisisAlertV2 | bearer | 278 |

## `crisis-incidents`

| Method | Path | Handler | Auth | Baris |
|---|---|---|---|---:|
| GET | `/v1/crisis-incidents` | listCrisisIncidents | bearer | 279 |
| POST | `/v1/crisis-incidents/{id}/resolve` | resolveCrisisIncident | bearer | 280 |

## `crisis-incident-log`

| Method | Path | Handler | Auth | Baris |
|---|---|---|---|---:|
| GET | `/v1/crisis-incident-log` | listCrisisIncidentLog | bearer | 281 |

## `sos-blast-status`

| Method | Path | Handler | Auth | Baris |
|---|---|---|---|---:|
| GET | `/v1/sos-blast-status` | listBlastStatus | bearer | 282 |

## `credentials`

| Method | Path | Handler | Auth | Baris |
|---|---|---|---|---:|
| POST | `/v1/credentials` | uploadCredentials | bearer | 284 |
| GET | `/v1/credentials/me` | getMyCredentials | bearer | 285 |

## `upload`

| Method | Path | Handler | Auth | Baris |
|---|---|---|---|---:|
| POST | `/v1/upload` | uploadFile | bearer | 287 |

## `chat-attachments`

| Method | Path | Handler | Auth | Baris |
|---|---|---|---|---:|
| POST | `/v1/chat-attachments` | uploadChatAttachment | bearer | 288 |
| GET | `/v1/chat-attachments/{attachment_id}` | getChatAttachment | bearer | 289 |

## `uploads`

| Method | Path | Handler | Auth | Baris |
|---|---|---|---|---:|
| GET | `/uploads/` | uploads (statis) | publik | 291 |

## `psych-tests`

| Method | Path | Handler | Auth | Baris |
|---|---|---|---|---:|
| GET | `/v1/psych-tests` | listPsychTests | publik | 293 |

## `doctors`

| Method | Path | Handler | Auth | Baris |
|---|---|---|---|---:|
| GET | `/v1/doctors/search` | searchDoctors | publik | 296 |
| GET | `/v1/doctors/{user_id}` | getDoctorProfile | publik | 297 |
| GET | `/v1/doctors/{user_id}/slots` | getDoctorAvailableSlots | publik | 298 |
| GET | `/v1/doctors/{user_id}/availability` | getDoctorAvailability | publik | 299 |
| GET | `/v1/doctors/{user_id}/reviews` | listDoctorReviews | publik | 347 |
| POST | `/v1/doctors/{user_id}/reviews` | createDoctorReview | bearer | 348 |

## `pricing`

| Method | Path | Handler | Auth | Baris |
|---|---|---|---|---:|
| GET | `/v1/pricing` | getPricing | bearer | 300 |

## `bookings`

| Method | Path | Handler | Auth | Baris |
|---|---|---|---|---:|
| POST | `/v1/bookings` | createBooking | bearer | 302 |
| POST | `/v1/bookings/{booking_id}/cancel` | cancelPendingBooking | bearer | 303 |
| GET | `/v1/bookings` | listBookings | bearer | 312 |

## `payments`

| Method | Path | Handler | Auth | Baris |
|---|---|---|---|---:|
| POST | `/v1/payments` | createPayment | bearer | 304 |
| POST | `/v1/payments/mark-paid` | markPaymentPaid | bearer | 305 |
| GET | `/v1/payments/{reference}` | getPaymentStatus | bearer | 307 |

## `config`

| Method | Path | Handler | Auth | Baris |
|---|---|---|---|---:|
| GET | `/v1/config/payment` | paymentConfigHandler | publik | 309 |

## `webhooks`

| Method | Path | Handler | Auth | Baris |
|---|---|---|---|---:|
| POST | `/v1/webhooks/payment` | paymentWebhook | signature | 311 |

## `care-packages`

| Method | Path | Handler | Auth | Baris |
|---|---|---|---|---:|
| POST | `/v1/care-packages` | createCarePackage | bearer | 314 |
| GET | `/v1/care-packages` | listCarePackages | bearer | 315 |
| POST | `/v1/care-packages/{package_id}/cancel` | cancelPendingCarePackage | bearer | 316 |

## `care-sessions`

| Method | Path | Handler | Auth | Baris |
|---|---|---|---|---:|
| POST | `/v1/care-sessions` | scheduleSession | bearer | 317 |
| GET | `/v1/care-sessions` | listCareSessions | bearer | 318 |
| PATCH | `/v1/care-sessions/{session_id}` | updateCareSession | bearer | 319 |
| POST | `/v1/care-sessions/{session_id}/reschedule` | rescheduleCareSession | bearer | 320 |
| POST | `/v1/care-sessions/{session_id}/meet-link` | ensureMeetLinkHandler | bearer | 322 |
| PUT | `/v1/care-sessions/{session_id}/meet-link` | setManualMeetLinkHandler | bearer | 325 |
| POST | `/v1/care-sessions/{session_id}/refund` | refundCareSession | bearer | 335 |

## `google`

| Method | Path | Handler | Auth | Baris |
|---|---|---|---|---:|
| GET | `/v1/google/status` | googleStatusHandler | bearer | 327 |

## `professionals`

| Method | Path | Handler | Auth | Baris |
|---|---|---|---|---:|
| GET | `/v1/professionals/{professional_id}/meet-status` | meetStatusHandler | bearer | 331 |

## `meet`

| Method | Path | Handler | Auth | Baris |
|---|---|---|---|---:|
| POST | `/v1/meet/quick` | createQuickMeet | bearer | 333 |

## `care-refunds`

| Method | Path | Handler | Auth | Baris |
|---|---|---|---|---:|
| GET | `/v1/care-refunds` | listCareRefunds | bearer | 336 |

## `chat-permission`

| Method | Path | Handler | Auth | Baris |
|---|---|---|---|---:|
| GET | `/v1/chat-permission` | chatPermission | bearer | 337 |

## `professional`

| Method | Path | Handler | Auth | Baris |
|---|---|---|---|---:|
| GET | `/v1/professional/time-off` | listTimeOff | bearer | 339 |
| POST | `/v1/professional/time-off` | addTimeOff | bearer | 340 |
| DELETE | `/v1/professional/time-off/{id}` | deleteTimeOff | bearer | 341 |
| PUT | `/v1/professional/pricing` | updatePricing | bearer | 342 |
| GET | `/v1/professional/schedules` | listMySchedules | bearer | 343 |
| PUT | `/v1/professional/schedules` | updateMySchedules | bearer | 344 |
| DELETE | `/v1/professional/schedules/{id}` | deleteMySchedule | bearer | 346 |

## `review-entitlements`

| Method | Path | Handler | Auth | Baris |
|---|---|---|---|---:|
| GET | `/v1/review-entitlements` | listReviewEntitlements | bearer | 349 |

## `earnings`

| Method | Path | Handler | Auth | Baris |
|---|---|---|---|---:|
| GET | `/v1/earnings` | earningsSummary | bearer | 350 |
| POST | `/v1/earnings/payout` | requestPayoutAll | bearer | 352 |
| POST | `/v1/earnings/{earning_id}/payout` | requestPayout | bearer | 353 |

## `e-prescriptions`

| Method | Path | Handler | Auth | Baris |
|---|---|---|---|---:|
| POST | `/v1/e-prescriptions` | createEPrescription | bearer | 354 |
| GET | `/v1/e-prescriptions` | listEPrescriptions | bearer | 355 |
| GET | `/v1/e-prescriptions/{id}` | getEPrescription | bearer | 356 |
| GET | `/v1/e-prescriptions/verify` | verifyEPrescriptionQR | publik | 358 |

## `health-record`

| Method | Path | Handler | Auth | Baris |
|---|---|---|---|---:|
| GET | `/v1/health-record` | getHealthRecord | bearer | 360 |
| PUT | `/v1/health-record` | updateHealthRecord | bearer | 361 |

## `goals`

| Method | Path | Handler | Auth | Baris |
|---|---|---|---|---:|
| GET | `/v1/goals` | listGoals | bearer | 363 |
| POST | `/v1/goals` | createGoal | bearer | 364 |
| PATCH | `/v1/goals/{goal_id}` | updateGoal | bearer | 365 |
| DELETE | `/v1/goals/{goal_id}` | deleteGoal | bearer | 366 |

## `habit-logs`

| Method | Path | Handler | Auth | Baris |
|---|---|---|---|---:|
| GET | `/v1/habit-logs` | listHabitLogs | bearer | 367 |
| POST | `/v1/habit-logs` | logHabit | bearer | 368 |

## `therapy-submissions`

| Method | Path | Handler | Auth | Baris |
|---|---|---|---|---:|
| GET | `/v1/therapy-submissions` | listTherapySubmissions | bearer | 370 |
| POST | `/v1/therapy-submissions` | createTherapySubmission | bearer | 371 |
| GET | `/v1/therapy-submissions/{submission_id}` | getTherapySubmission | bearer | 372 |
| POST | `/v1/therapy-submissions/{submission_id}/share` | shareTherapySubmission | bearer | 373 |
| DELETE | `/v1/therapy-submissions/{submission_id}` | deleteTherapySubmission | bearer | 374 |

## `admin`

| Method | Path | Handler | Auth | Baris |
|---|---|---|---|---:|
| GET | `/v1/admin/users` | listAdminUsers | bearer (admin) | 376 |
| PATCH | `/v1/admin/users/{user_id}` | updateAdminUser | bearer (admin) | 377 |
| DELETE | `/v1/admin/users/{user_id}` | deleteAdminUser | bearer (admin) | 378 |
| GET | `/v1/admin/credentials/pending` | listPendingCredentials | bearer (admin) | 379 |
| POST | `/v1/admin/credentials/{id}/verify` | verifyCredential | bearer (admin) | 380 |
| POST | `/v1/admin/doctors` | createAdminDoctor | bearer (admin) | 381 |
| GET | `/v1/admin/doctors` | listAdminDoctors | bearer (admin) | 382 |
| GET | `/v1/admin/doctors/{user_id}` | getAdminDoctor | bearer (admin) | 383 |
| PUT | `/v1/admin/doctors/{user_id}` | updateAdminDoctor | bearer (admin) | 384 |
| GET | `/v1/admin/overview` | adminOverview | bearer (admin) | 389 |
| GET | `/v1/admin/payments` | listAdminPayments | bearer (admin) | 390 |
| GET | `/v1/admin/payments/{payment_id}` | getAdminPayment | bearer (admin) | 391 |
| POST | `/v1/admin/payments/{payment_id}/override` | overrideAdminPayment | bearer (admin) | 392 |
| GET | `/v1/admin/pricing` | listAdminPricing | bearer (admin) | 393 |
| PUT | `/v1/admin/pricing/{professional_id}` | updateAdminPricing | bearer (admin) | 394 |
| GET | `/v1/admin/refunds` | listAdminRefunds | bearer (admin) | 395 |
| POST | `/v1/admin/users/{user_id}/reset-password` | resetAdminUserPassword | bearer (admin) | 396 |
| POST | `/v1/admin/users/{user_id}/revoke-sessions` | revokeAdminUserSessions | bearer (admin) | 397 |

