# Inventaris Rute API Malva

> **Dibuat otomatis oleh `go run ./cmd/apidoc` — jangan diedit manual.**
> Sumber kebenaran: `backend/internal/server/server.go` (fungsi `Routes()`).
> Regenerasi: `cd backend && go run ./cmd/apidoc`
> Verifikasi sinkron: `cd backend && go run ./cmd/apidoc -check`

Total endpoint API: **125** (+1 penyajian berkas statis `GET /uploads/`).

## Ringkasan per Tag

| Tag | Jumlah Endpoint |
|---|---:|
| system | 2 |
| auth | 11 |
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
| POST | `/v1/auth/bind-google` | bindGoogle | bearer | 210 |
| GET | `/v1/auth/google-identity` | googleIdentityStatus | bearer | 211 |
| POST | `/v1/auth/google-token-exchange` | exchangeGoogleToken | bearer | 212 |
| POST | `/v1/auth/complete-professional` | completeProfessionalProfile | bearer | 213 |
| POST | `/v1/auth/refresh` | refresh | publik | 214 |
| POST | `/v1/auth/logout` | logout | publik | 215 |
| POST | `/v1/auth/change-password` | changePassword | bearer | 216 |

## `me`

| Method | Path | Handler | Auth | Baris |
|---|---|---|---|---:|
| GET | `/v1/me` | me | bearer | 217 |
| PATCH | `/v1/me` | updateMe | bearer | 218 |

## `device-tokens`

| Method | Path | Handler | Auth | Baris |
|---|---|---|---|---:|
| POST | `/v1/device-tokens` | upsertDeviceToken | bearer | 219 |

## `screenings`

| Method | Path | Handler | Auth | Baris |
|---|---|---|---|---:|
| POST | `/v1/screenings` | createScreening | bearer | 220 |
| GET | `/v1/screenings` | listScreenings | bearer | 221 |
| POST | `/v1/screenings/{screening_id}/review` | reviewScreening | bearer | 222 |

## `screening-reviews`

| Method | Path | Handler | Auth | Baris |
|---|---|---|---|---:|
| GET | `/v1/screening-reviews` | listScreeningReviews | bearer | 223 |

## `patient-professional-links`

| Method | Path | Handler | Auth | Baris |
|---|---|---|---|---:|
| GET | `/v1/patient-professional-links` | listPatientProfessionalLinks | bearer | 224 |
| POST | `/v1/patient-professional-links` | linkPatientToProfessional | bearer | 225 |

## `professional-notes`

| Method | Path | Handler | Auth | Baris |
|---|---|---|---|---:|
| GET | `/v1/professional-notes` | listProfessionalNotes | bearer | 226 |
| POST | `/v1/professional-notes` | createProfessionalNote | bearer | 227 |

## `follow-ups`

| Method | Path | Handler | Auth | Baris |
|---|---|---|---|---:|
| GET | `/v1/follow-ups` | listFollowUps | bearer | 228 |
| POST | `/v1/follow-ups` | createFollowUp | bearer | 229 |
| PATCH | `/v1/follow-ups/{follow_up_id}/read` | markFollowUpRead | bearer | 230 |

## `mood-checkins`

| Method | Path | Handler | Auth | Baris |
|---|---|---|---|---:|
| GET | `/v1/mood-checkins` | listMoodCheckins | bearer | 231 |
| POST | `/v1/mood-checkins` | createMoodCheckin | bearer | 232 |

## `diary-entries`

| Method | Path | Handler | Auth | Baris |
|---|---|---|---|---:|
| GET | `/v1/diary-entries` | listDiaryEntries | bearer | 233 |
| POST | `/v1/diary-entries` | createDiaryEntry | bearer | 234 |
| PUT | `/v1/diary-entries/{diary_id}` | updateDiaryEntry | bearer | 235 |
| DELETE | `/v1/diary-entries/{diary_id}` | deleteDiaryEntry | bearer | 236 |
| PATCH | `/v1/diary-entries/{diary_id}/feedback` | updateDiaryFeedback | bearer | 237 |

## `medications`

| Method | Path | Handler | Auth | Baris |
|---|---|---|---|---:|
| GET | `/v1/medications` | listMedications | bearer | 238 |
| POST | `/v1/medications` | createMedication | bearer | 239 |
| PUT | `/v1/medications/{medication_id}` | updateMedication | bearer | 243 |
| DELETE | `/v1/medications/{medication_id}` | deleteMedication | bearer | 244 |

## `medication-logs`

| Method | Path | Handler | Auth | Baris |
|---|---|---|---|---:|
| GET | `/v1/medication-logs` | listMedicationLogs | bearer | 245 |
| POST | `/v1/medication-logs` | createMedicationLog | bearer | 246 |

## `timeline`

| Method | Path | Handler | Auth | Baris |
|---|---|---|---|---:|
| GET | `/v1/timeline` | timeline | bearer | 247 |

## `audit-logs`

| Method | Path | Handler | Auth | Baris |
|---|---|---|---|---:|
| GET | `/v1/audit-logs` | auditLogs | bearer | 248 |

## `privacy`

| Method | Path | Handler | Auth | Baris |
|---|---|---|---|---:|
| GET | `/v1/privacy/consents` | getPrivacyConsent | bearer | 249 |
| PUT | `/v1/privacy/consents` | updatePrivacyConsent | bearer | 250 |

## `messages`

| Method | Path | Handler | Auth | Baris |
|---|---|---|---|---:|
| GET | `/v1/messages` | listMessages | bearer | 251 |
| POST | `/v1/messages` | sendMessage | bearer | 252 |

## `notifications`

| Method | Path | Handler | Auth | Baris |
|---|---|---|---|---:|
| GET | `/v1/notifications` | listNotifications | bearer | 253 |
| PATCH | `/v1/notifications/read-all` | markAllNotificationsRead | bearer | 254 |
| PATCH | `/v1/notifications/{notification_id}/read` | markNotificationRead | bearer | 255 |
| POST | `/v1/notifications/test` | testNotification | bearer | 256 |

## `realtime`

| Method | Path | Handler | Auth | Baris |
|---|---|---|---|---:|
| GET | `/v1/realtime/ws` | realtimeWS | bearer (query token) | 257 |

## `emergency-contacts`

| Method | Path | Handler | Auth | Baris |
|---|---|---|---|---:|
| GET | `/v1/emergency-contacts` | listEmergencyContacts | bearer | 259 |
| POST | `/v1/emergency-contacts` | createEmergencyContact | bearer | 260 |
| PUT | `/v1/emergency-contacts/{id}` | updateEmergencyContact | bearer | 261 |
| DELETE | `/v1/emergency-contacts/{id}` | deleteEmergencyContact | bearer | 262 |

## `crisis-alerts`

| Method | Path | Handler | Auth | Baris |
|---|---|---|---|---:|
| POST | `/v1/crisis-alerts` | handleCrisisAlertV2 | bearer | 263 |

## `crisis-incidents`

| Method | Path | Handler | Auth | Baris |
|---|---|---|---|---:|
| GET | `/v1/crisis-incidents` | listCrisisIncidents | bearer | 264 |
| POST | `/v1/crisis-incidents/{id}/resolve` | resolveCrisisIncident | bearer | 265 |

## `sos-blast-status`

| Method | Path | Handler | Auth | Baris |
|---|---|---|---|---:|
| GET | `/v1/sos-blast-status` | listBlastStatus | bearer | 266 |

## `credentials`

| Method | Path | Handler | Auth | Baris |
|---|---|---|---|---:|
| POST | `/v1/credentials` | uploadCredentials | bearer | 268 |
| GET | `/v1/credentials/me` | getMyCredentials | bearer | 269 |

## `upload`

| Method | Path | Handler | Auth | Baris |
|---|---|---|---|---:|
| POST | `/v1/upload` | uploadFile | bearer | 271 |

## `uploads`

| Method | Path | Handler | Auth | Baris |
|---|---|---|---|---:|
| GET | `/uploads/` | uploads (statis) | publik | 273 |

## `psych-tests`

| Method | Path | Handler | Auth | Baris |
|---|---|---|---|---:|
| GET | `/v1/psych-tests` | listPsychTests | publik | 275 |

## `doctors`

| Method | Path | Handler | Auth | Baris |
|---|---|---|---|---:|
| GET | `/v1/doctors/search` | searchDoctors | publik | 278 |
| GET | `/v1/doctors/{user_id}` | getDoctorProfile | publik | 279 |
| GET | `/v1/doctors/{user_id}/slots` | getDoctorAvailableSlots | publik | 280 |
| GET | `/v1/doctors/{user_id}/availability` | getDoctorAvailability | publik | 281 |
| GET | `/v1/doctors/{user_id}/reviews` | listDoctorReviews | publik | 318 |
| POST | `/v1/doctors/{user_id}/reviews` | createDoctorReview | bearer | 319 |

## `pricing`

| Method | Path | Handler | Auth | Baris |
|---|---|---|---|---:|
| GET | `/v1/pricing` | getPricing | bearer | 282 |

## `bookings`

| Method | Path | Handler | Auth | Baris |
|---|---|---|---|---:|
| POST | `/v1/bookings` | createBooking | bearer | 284 |
| POST | `/v1/bookings/{booking_id}/cancel` | cancelPendingBooking | bearer | 285 |
| GET | `/v1/bookings` | listBookings | bearer | 290 |

## `payments`

| Method | Path | Handler | Auth | Baris |
|---|---|---|---|---:|
| POST | `/v1/payments` | createPayment | bearer | 286 |
| POST | `/v1/payments/mark-paid` | markPaymentPaid | bearer | 287 |

## `webhooks`

| Method | Path | Handler | Auth | Baris |
|---|---|---|---|---:|
| POST | `/v1/webhooks/payment` | paymentWebhook | signature | 289 |

## `care-packages`

| Method | Path | Handler | Auth | Baris |
|---|---|---|---|---:|
| POST | `/v1/care-packages` | createCarePackage | bearer | 292 |
| GET | `/v1/care-packages` | listCarePackages | bearer | 293 |
| POST | `/v1/care-packages/{package_id}/cancel` | cancelPendingCarePackage | bearer | 294 |

## `care-sessions`

| Method | Path | Handler | Auth | Baris |
|---|---|---|---|---:|
| POST | `/v1/care-sessions` | scheduleSession | bearer | 295 |
| GET | `/v1/care-sessions` | listCareSessions | bearer | 296 |
| PATCH | `/v1/care-sessions/{session_id}` | updateCareSession | bearer | 297 |
| POST | `/v1/care-sessions/{session_id}/reschedule` | rescheduleCareSession | bearer | 298 |
| POST | `/v1/care-sessions/{session_id}/meet-link` | ensureMeetLinkHandler | bearer | 300 |
| POST | `/v1/care-sessions/{session_id}/refund` | refundCareSession | bearer | 306 |

## `google`

| Method | Path | Handler | Auth | Baris |
|---|---|---|---|---:|
| GET | `/v1/google/status` | googleStatusHandler | bearer | 302 |

## `meet`

| Method | Path | Handler | Auth | Baris |
|---|---|---|---|---:|
| POST | `/v1/meet/quick` | createQuickMeet | bearer | 304 |

## `care-refunds`

| Method | Path | Handler | Auth | Baris |
|---|---|---|---|---:|
| GET | `/v1/care-refunds` | listCareRefunds | bearer | 307 |

## `chat-permission`

| Method | Path | Handler | Auth | Baris |
|---|---|---|---|---:|
| GET | `/v1/chat-permission` | chatPermission | bearer | 308 |

## `professional`

| Method | Path | Handler | Auth | Baris |
|---|---|---|---|---:|
| GET | `/v1/professional/time-off` | listTimeOff | bearer | 310 |
| POST | `/v1/professional/time-off` | addTimeOff | bearer | 311 |
| DELETE | `/v1/professional/time-off/{id}` | deleteTimeOff | bearer | 312 |
| PUT | `/v1/professional/pricing` | updatePricing | bearer | 313 |
| GET | `/v1/professional/schedules` | listMySchedules | bearer | 314 |
| PUT | `/v1/professional/schedules` | updateMySchedules | bearer | 315 |
| DELETE | `/v1/professional/schedules/{id}` | deleteMySchedule | bearer | 317 |

## `earnings`

| Method | Path | Handler | Auth | Baris |
|---|---|---|---|---:|
| GET | `/v1/earnings` | earningsSummary | bearer | 320 |
| POST | `/v1/earnings/payout` | requestPayoutAll | bearer | 322 |
| POST | `/v1/earnings/{earning_id}/payout` | requestPayout | bearer | 323 |

## `e-prescriptions`

| Method | Path | Handler | Auth | Baris |
|---|---|---|---|---:|
| POST | `/v1/e-prescriptions` | createEPrescription | bearer | 324 |
| GET | `/v1/e-prescriptions` | listEPrescriptions | bearer | 325 |
| GET | `/v1/e-prescriptions/{id}` | getEPrescription | bearer | 326 |
| GET | `/v1/e-prescriptions/verify` | verifyEPrescriptionQR | publik | 328 |

## `health-record`

| Method | Path | Handler | Auth | Baris |
|---|---|---|---|---:|
| GET | `/v1/health-record` | getHealthRecord | bearer | 330 |
| PUT | `/v1/health-record` | updateHealthRecord | bearer | 331 |

## `goals`

| Method | Path | Handler | Auth | Baris |
|---|---|---|---|---:|
| GET | `/v1/goals` | listGoals | bearer | 333 |
| POST | `/v1/goals` | createGoal | bearer | 334 |
| PATCH | `/v1/goals/{goal_id}` | updateGoal | bearer | 335 |
| DELETE | `/v1/goals/{goal_id}` | deleteGoal | bearer | 336 |

## `habit-logs`

| Method | Path | Handler | Auth | Baris |
|---|---|---|---|---:|
| GET | `/v1/habit-logs` | listHabitLogs | bearer | 337 |
| POST | `/v1/habit-logs` | logHabit | bearer | 338 |

## `therapy-submissions`

| Method | Path | Handler | Auth | Baris |
|---|---|---|---|---:|
| GET | `/v1/therapy-submissions` | listTherapySubmissions | bearer | 340 |
| POST | `/v1/therapy-submissions` | createTherapySubmission | bearer | 341 |
| GET | `/v1/therapy-submissions/{submission_id}` | getTherapySubmission | bearer | 342 |
| POST | `/v1/therapy-submissions/{submission_id}/share` | shareTherapySubmission | bearer | 343 |
| DELETE | `/v1/therapy-submissions/{submission_id}` | deleteTherapySubmission | bearer | 344 |

## `admin`

| Method | Path | Handler | Auth | Baris |
|---|---|---|---|---:|
| GET | `/v1/admin/users` | listAdminUsers | bearer (admin) | 346 |
| PATCH | `/v1/admin/users/{user_id}` | updateAdminUser | bearer (admin) | 347 |
| DELETE | `/v1/admin/users/{user_id}` | deleteAdminUser | bearer (admin) | 348 |
| GET | `/v1/admin/credentials/pending` | listPendingCredentials | bearer (admin) | 349 |
| POST | `/v1/admin/credentials/{id}/verify` | verifyCredential | bearer (admin) | 350 |
| POST | `/v1/admin/doctors` | createAdminDoctor | bearer (admin) | 351 |
| GET | `/v1/admin/doctors` | listAdminDoctors | bearer (admin) | 352 |
| GET | `/v1/admin/doctors/{user_id}` | getAdminDoctor | bearer (admin) | 353 |
| PUT | `/v1/admin/doctors/{user_id}` | updateAdminDoctor | bearer (admin) | 354 |

