# Inventaris Rute API Malva

> **Dibuat otomatis oleh `go run ./cmd/apidoc` — jangan diedit manual.**
> Sumber kebenaran: `backend/internal/server/server.go` (fungsi `Routes()`).
> Regenerasi: `cd backend && go run ./cmd/apidoc`
> Verifikasi sinkron: `cd backend && go run ./cmd/apidoc -check`

Total endpoint API: **153** (+1 penyajian berkas statis `GET /uploads/`).

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
| diary-entries | 9 |
| diary-media | 2 |
| medications | 4 |
| medication-logs | 2 |
| timeline | 1 |
| audit-logs | 1 |
| privacy | 2 |
| messages | 3 |
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
| e-prescriptions | 6 |
| health-record | 2 |
| goals | 4 |
| habit-logs | 2 |
| therapy-submissions | 5 |
| admin | 18 |

## `system`

| Method | Path | Handler | Auth | Baris |
|---|---|---|---|---:|
| GET | `/` | root | publik | 216 |
| GET | `/healthz` | health | publik | 217 |

## `auth`

| Method | Path | Handler | Auth | Baris |
|---|---|---|---|---:|
| POST | `/v1/auth/register` | register | publik | 218 |
| POST | `/v1/auth/login` | login | publik | 219 |
| POST | `/v1/auth/google` | googleLogin | publik | 220 |
| POST | `/v1/auth/link-google` | linkGoogle | bearer | 221 |
| POST | `/v1/auth/bind-google` | bindGoogle | bearer | 222 |
| POST | `/v1/auth/unbind-google` | unbindGoogle | bearer | 223 |
| GET | `/v1/auth/google-identity` | googleIdentityStatus | bearer | 224 |
| POST | `/v1/auth/google-token-exchange` | exchangeGoogleToken | bearer | 225 |
| POST | `/v1/auth/complete-professional` | completeProfessionalProfile | bearer | 226 |
| POST | `/v1/auth/refresh` | refresh | publik | 227 |
| POST | `/v1/auth/logout` | logout | publik | 228 |
| POST | `/v1/auth/change-password` | changePassword | bearer | 229 |

## `me`

| Method | Path | Handler | Auth | Baris |
|---|---|---|---|---:|
| GET | `/v1/me` | me | bearer | 230 |
| PATCH | `/v1/me` | updateMe | bearer | 231 |

## `device-tokens`

| Method | Path | Handler | Auth | Baris |
|---|---|---|---|---:|
| POST | `/v1/device-tokens` | upsertDeviceToken | bearer | 232 |
| DELETE | `/v1/device-tokens` | deleteDeviceToken | bearer | 235 |

## `screenings`

| Method | Path | Handler | Auth | Baris |
|---|---|---|---|---:|
| POST | `/v1/screenings` | createScreening | bearer | 236 |
| GET | `/v1/screenings` | listScreenings | bearer | 237 |
| POST | `/v1/screenings/{screening_id}/review` | reviewScreening | bearer | 238 |

## `screening-reviews`

| Method | Path | Handler | Auth | Baris |
|---|---|---|---|---:|
| GET | `/v1/screening-reviews` | listScreeningReviews | bearer | 239 |

## `patient-professional-links`

| Method | Path | Handler | Auth | Baris |
|---|---|---|---|---:|
| GET | `/v1/patient-professional-links` | listPatientProfessionalLinks | bearer | 240 |
| POST | `/v1/patient-professional-links` | linkPatientToProfessional | bearer | 241 |

## `professional-notes`

| Method | Path | Handler | Auth | Baris |
|---|---|---|---|---:|
| GET | `/v1/professional-notes` | listProfessionalNotes | bearer | 242 |
| POST | `/v1/professional-notes` | createProfessionalNote | bearer | 243 |

## `follow-ups`

| Method | Path | Handler | Auth | Baris |
|---|---|---|---|---:|
| GET | `/v1/follow-ups` | listFollowUps | bearer | 244 |
| POST | `/v1/follow-ups` | createFollowUp | bearer | 245 |
| PATCH | `/v1/follow-ups/{follow_up_id}/read` | markFollowUpRead | bearer | 246 |

## `mood-checkins`

| Method | Path | Handler | Auth | Baris |
|---|---|---|---|---:|
| GET | `/v1/mood-checkins` | listMoodCheckins | bearer | 247 |
| POST | `/v1/mood-checkins` | createMoodCheckin | bearer | 248 |

## `diary-entries`

| Method | Path | Handler | Auth | Baris |
|---|---|---|---|---:|
| GET | `/v1/diary-entries` | listDiaryEntries | bearer | 249 |
| POST | `/v1/diary-entries` | createDiaryEntry | bearer | 252 |
| GET | `/v1/diary-entries/{diary_id}` | getDiaryEntry | bearer | 253 |
| PUT | `/v1/diary-entries/{diary_id}` | updateDiaryEntry | bearer | 254 |
| DELETE | `/v1/diary-entries/{diary_id}` | deleteDiaryEntry | bearer | 255 |
| GET | `/v1/diary-entries/{diary_id}/access` | getDiaryAccess | bearer | 256 |
| PUT | `/v1/diary-entries/{diary_id}/access/{professional_id}` | setDiaryRecipient | bearer | 257 |
| DELETE | `/v1/diary-entries/{diary_id}/access/{professional_id}` | setDiaryRecipient | bearer | 258 |
| PATCH | `/v1/diary-entries/{diary_id}/feedback` | updateDiaryFeedback | bearer | 259 |

## `diary-media`

| Method | Path | Handler | Auth | Baris |
|---|---|---|---|---:|
| POST | `/v1/diary-media` | uploadDiaryImage | bearer | 250 |
| GET | `/v1/diary-media/{patient_id}/{filename}` | getDiaryImage | bearer | 251 |

## `medications`

| Method | Path | Handler | Auth | Baris |
|---|---|---|---|---:|
| GET | `/v1/medications` | listMedications | bearer | 260 |
| POST | `/v1/medications` | createMedication | bearer | 261 |
| PUT | `/v1/medications/{medication_id}` | updateMedication | bearer | 265 |
| DELETE | `/v1/medications/{medication_id}` | deleteMedication | bearer | 266 |

## `medication-logs`

| Method | Path | Handler | Auth | Baris |
|---|---|---|---|---:|
| GET | `/v1/medication-logs` | listMedicationLogs | bearer | 267 |
| POST | `/v1/medication-logs` | createMedicationLog | bearer | 268 |

## `timeline`

| Method | Path | Handler | Auth | Baris |
|---|---|---|---|---:|
| GET | `/v1/timeline` | timeline | bearer | 269 |

## `audit-logs`

| Method | Path | Handler | Auth | Baris |
|---|---|---|---|---:|
| GET | `/v1/audit-logs` | auditLogs | bearer | 270 |

## `privacy`

| Method | Path | Handler | Auth | Baris |
|---|---|---|---|---:|
| GET | `/v1/privacy/consents` | getPrivacyConsent | bearer | 271 |
| PUT | `/v1/privacy/consents` | updatePrivacyConsent | bearer | 272 |

## `messages`

| Method | Path | Handler | Auth | Baris |
|---|---|---|---|---:|
| GET | `/v1/messages` | listMessages | bearer | 273 |
| POST | `/v1/messages` | sendMessage | bearer | 274 |
| DELETE | `/v1/messages/{message_id}` | deleteChatMessage | bearer | 275 |

## `notifications`

| Method | Path | Handler | Auth | Baris |
|---|---|---|---|---:|
| GET | `/v1/notifications` | listNotifications | bearer | 276 |
| PATCH | `/v1/notifications/read-all` | markAllNotificationsRead | bearer | 277 |
| PATCH | `/v1/notifications/{notification_id}/read` | markNotificationRead | bearer | 278 |
| POST | `/v1/notifications/test` | testNotification | bearer | 279 |

## `realtime`

| Method | Path | Handler | Auth | Baris |
|---|---|---|---|---:|
| GET | `/v1/realtime/ws` | realtimeWS | bearer (query token) | 280 |

## `emergency-contacts`

| Method | Path | Handler | Auth | Baris |
|---|---|---|---|---:|
| GET | `/v1/emergency-contacts` | listEmergencyContacts | bearer | 282 |
| POST | `/v1/emergency-contacts` | createEmergencyContact | bearer | 283 |
| PUT | `/v1/emergency-contacts/{id}` | updateEmergencyContact | bearer | 284 |
| DELETE | `/v1/emergency-contacts/{id}` | deleteEmergencyContact | bearer | 285 |

## `crisis-alerts`

| Method | Path | Handler | Auth | Baris |
|---|---|---|---|---:|
| POST | `/v1/crisis-alerts` | handleCrisisAlertV2 | bearer | 286 |

## `crisis-incidents`

| Method | Path | Handler | Auth | Baris |
|---|---|---|---|---:|
| GET | `/v1/crisis-incidents` | listCrisisIncidents | bearer | 287 |
| POST | `/v1/crisis-incidents/{id}/resolve` | resolveCrisisIncident | bearer | 288 |

## `crisis-incident-log`

| Method | Path | Handler | Auth | Baris |
|---|---|---|---|---:|
| GET | `/v1/crisis-incident-log` | listCrisisIncidentLog | bearer | 289 |

## `sos-blast-status`

| Method | Path | Handler | Auth | Baris |
|---|---|---|---|---:|
| GET | `/v1/sos-blast-status` | listBlastStatus | bearer | 290 |

## `credentials`

| Method | Path | Handler | Auth | Baris |
|---|---|---|---|---:|
| POST | `/v1/credentials` | uploadCredentials | bearer | 292 |
| GET | `/v1/credentials/me` | getMyCredentials | bearer | 293 |

## `upload`

| Method | Path | Handler | Auth | Baris |
|---|---|---|---|---:|
| POST | `/v1/upload` | uploadFile | bearer | 295 |

## `chat-attachments`

| Method | Path | Handler | Auth | Baris |
|---|---|---|---|---:|
| POST | `/v1/chat-attachments` | uploadChatAttachment | bearer | 296 |
| GET | `/v1/chat-attachments/{attachment_id}` | getChatAttachment | bearer | 297 |

## `uploads`

| Method | Path | Handler | Auth | Baris |
|---|---|---|---|---:|
| GET | `/uploads/` | uploads (statis) | publik | 299 |

## `psych-tests`

| Method | Path | Handler | Auth | Baris |
|---|---|---|---|---:|
| GET | `/v1/psych-tests` | listPsychTests | publik | 301 |

## `doctors`

| Method | Path | Handler | Auth | Baris |
|---|---|---|---|---:|
| GET | `/v1/doctors/search` | searchDoctors | publik | 304 |
| GET | `/v1/doctors/{user_id}` | getDoctorProfile | publik | 305 |
| GET | `/v1/doctors/{user_id}/slots` | getDoctorAvailableSlots | publik | 306 |
| GET | `/v1/doctors/{user_id}/availability` | getDoctorAvailability | publik | 307 |
| GET | `/v1/doctors/{user_id}/reviews` | listDoctorReviews | publik | 355 |
| POST | `/v1/doctors/{user_id}/reviews` | createDoctorReview | bearer | 356 |

## `pricing`

| Method | Path | Handler | Auth | Baris |
|---|---|---|---|---:|
| GET | `/v1/pricing` | getPricing | bearer | 308 |

## `bookings`

| Method | Path | Handler | Auth | Baris |
|---|---|---|---|---:|
| POST | `/v1/bookings` | createBooking | bearer | 310 |
| POST | `/v1/bookings/{booking_id}/cancel` | cancelPendingBooking | bearer | 311 |
| GET | `/v1/bookings` | listBookings | bearer | 320 |

## `payments`

| Method | Path | Handler | Auth | Baris |
|---|---|---|---|---:|
| POST | `/v1/payments` | createPayment | bearer | 312 |
| POST | `/v1/payments/mark-paid` | markPaymentPaid | bearer | 313 |
| GET | `/v1/payments/{reference}` | getPaymentStatus | bearer | 315 |

## `config`

| Method | Path | Handler | Auth | Baris |
|---|---|---|---|---:|
| GET | `/v1/config/payment` | paymentConfigHandler | publik | 317 |

## `webhooks`

| Method | Path | Handler | Auth | Baris |
|---|---|---|---|---:|
| POST | `/v1/webhooks/payment` | paymentWebhook | signature | 319 |

## `care-packages`

| Method | Path | Handler | Auth | Baris |
|---|---|---|---|---:|
| POST | `/v1/care-packages` | createCarePackage | bearer | 322 |
| GET | `/v1/care-packages` | listCarePackages | bearer | 323 |
| POST | `/v1/care-packages/{package_id}/cancel` | cancelPendingCarePackage | bearer | 324 |

## `care-sessions`

| Method | Path | Handler | Auth | Baris |
|---|---|---|---|---:|
| POST | `/v1/care-sessions` | scheduleSession | bearer | 325 |
| GET | `/v1/care-sessions` | listCareSessions | bearer | 326 |
| PATCH | `/v1/care-sessions/{session_id}` | updateCareSession | bearer | 327 |
| POST | `/v1/care-sessions/{session_id}/reschedule` | rescheduleCareSession | bearer | 328 |
| POST | `/v1/care-sessions/{session_id}/meet-link` | ensureMeetLinkHandler | bearer | 330 |
| PUT | `/v1/care-sessions/{session_id}/meet-link` | setManualMeetLinkHandler | bearer | 333 |
| POST | `/v1/care-sessions/{session_id}/refund` | refundCareSession | bearer | 343 |

## `google`

| Method | Path | Handler | Auth | Baris |
|---|---|---|---|---:|
| GET | `/v1/google/status` | googleStatusHandler | bearer | 335 |

## `professionals`

| Method | Path | Handler | Auth | Baris |
|---|---|---|---|---:|
| GET | `/v1/professionals/{professional_id}/meet-status` | meetStatusHandler | bearer | 339 |

## `meet`

| Method | Path | Handler | Auth | Baris |
|---|---|---|---|---:|
| POST | `/v1/meet/quick` | createQuickMeet | bearer | 341 |

## `care-refunds`

| Method | Path | Handler | Auth | Baris |
|---|---|---|---|---:|
| GET | `/v1/care-refunds` | listCareRefunds | bearer | 344 |

## `chat-permission`

| Method | Path | Handler | Auth | Baris |
|---|---|---|---|---:|
| GET | `/v1/chat-permission` | chatPermission | bearer | 345 |

## `professional`

| Method | Path | Handler | Auth | Baris |
|---|---|---|---|---:|
| GET | `/v1/professional/time-off` | listTimeOff | bearer | 347 |
| POST | `/v1/professional/time-off` | addTimeOff | bearer | 348 |
| DELETE | `/v1/professional/time-off/{id}` | deleteTimeOff | bearer | 349 |
| PUT | `/v1/professional/pricing` | updatePricing | bearer | 350 |
| GET | `/v1/professional/schedules` | listMySchedules | bearer | 351 |
| PUT | `/v1/professional/schedules` | updateMySchedules | bearer | 352 |
| DELETE | `/v1/professional/schedules/{id}` | deleteMySchedule | bearer | 354 |

## `review-entitlements`

| Method | Path | Handler | Auth | Baris |
|---|---|---|---|---:|
| GET | `/v1/review-entitlements` | listReviewEntitlements | bearer | 357 |

## `earnings`

| Method | Path | Handler | Auth | Baris |
|---|---|---|---|---:|
| GET | `/v1/earnings` | earningsSummary | bearer | 358 |
| POST | `/v1/earnings/payout` | requestPayoutAll | bearer | 360 |
| POST | `/v1/earnings/{earning_id}/payout` | requestPayout | bearer | 361 |

## `e-prescriptions`

| Method | Path | Handler | Auth | Baris |
|---|---|---|---|---:|
| POST | `/v1/e-prescriptions` | createEPrescription | bearer | 362 |
| GET | `/v1/e-prescriptions` | listEPrescriptions | bearer | 363 |
| GET | `/v1/e-prescriptions/{id}` | getEPrescription | bearer | 364 |
| PUT | `/v1/e-prescriptions/{id}` | updateEPrescription | bearer | 365 |
| DELETE | `/v1/e-prescriptions/{id}` | deleteEPrescription | bearer | 366 |
| GET | `/v1/e-prescriptions/verify` | verifyEPrescriptionQR | publik | 368 |

## `health-record`

| Method | Path | Handler | Auth | Baris |
|---|---|---|---|---:|
| GET | `/v1/health-record` | getHealthRecord | bearer | 370 |
| PUT | `/v1/health-record` | updateHealthRecord | bearer | 371 |

## `goals`

| Method | Path | Handler | Auth | Baris |
|---|---|---|---|---:|
| GET | `/v1/goals` | listGoals | bearer | 373 |
| POST | `/v1/goals` | createGoal | bearer | 374 |
| PATCH | `/v1/goals/{goal_id}` | updateGoal | bearer | 375 |
| DELETE | `/v1/goals/{goal_id}` | deleteGoal | bearer | 376 |

## `habit-logs`

| Method | Path | Handler | Auth | Baris |
|---|---|---|---|---:|
| GET | `/v1/habit-logs` | listHabitLogs | bearer | 377 |
| POST | `/v1/habit-logs` | logHabit | bearer | 378 |

## `therapy-submissions`

| Method | Path | Handler | Auth | Baris |
|---|---|---|---|---:|
| GET | `/v1/therapy-submissions` | listTherapySubmissions | bearer | 380 |
| POST | `/v1/therapy-submissions` | createTherapySubmission | bearer | 381 |
| GET | `/v1/therapy-submissions/{submission_id}` | getTherapySubmission | bearer | 382 |
| POST | `/v1/therapy-submissions/{submission_id}/share` | shareTherapySubmission | bearer | 383 |
| DELETE | `/v1/therapy-submissions/{submission_id}` | deleteTherapySubmission | bearer | 384 |

## `admin`

| Method | Path | Handler | Auth | Baris |
|---|---|---|---|---:|
| GET | `/v1/admin/users` | listAdminUsers | bearer (admin) | 386 |
| PATCH | `/v1/admin/users/{user_id}` | updateAdminUser | bearer (admin) | 387 |
| DELETE | `/v1/admin/users/{user_id}` | deleteAdminUser | bearer (admin) | 388 |
| GET | `/v1/admin/credentials/pending` | listPendingCredentials | bearer (admin) | 389 |
| POST | `/v1/admin/credentials/{id}/verify` | verifyCredential | bearer (admin) | 390 |
| POST | `/v1/admin/doctors` | createAdminDoctor | bearer (admin) | 391 |
| GET | `/v1/admin/doctors` | listAdminDoctors | bearer (admin) | 392 |
| GET | `/v1/admin/doctors/{user_id}` | getAdminDoctor | bearer (admin) | 393 |
| PUT | `/v1/admin/doctors/{user_id}` | updateAdminDoctor | bearer (admin) | 394 |
| GET | `/v1/admin/overview` | adminOverview | bearer (admin) | 399 |
| GET | `/v1/admin/payments` | listAdminPayments | bearer (admin) | 400 |
| GET | `/v1/admin/payments/{payment_id}` | getAdminPayment | bearer (admin) | 401 |
| POST | `/v1/admin/payments/{payment_id}/override` | overrideAdminPayment | bearer (admin) | 402 |
| GET | `/v1/admin/pricing` | listAdminPricing | bearer (admin) | 403 |
| PUT | `/v1/admin/pricing/{professional_id}` | updateAdminPricing | bearer (admin) | 404 |
| GET | `/v1/admin/refunds` | listAdminRefunds | bearer (admin) | 405 |
| POST | `/v1/admin/users/{user_id}/reset-password` | resetAdminUserPassword | bearer (admin) | 406 |
| POST | `/v1/admin/users/{user_id}/revoke-sessions` | revokeAdminUserSessions | bearer (admin) | 407 |

