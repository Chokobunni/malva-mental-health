# Inventaris Rute API Malva

> **Dibuat otomatis oleh `go run ./cmd/apidoc` — jangan diedit manual.**
> Sumber kebenaran: `backend/internal/server/server.go` (fungsi `Routes()`).
> Regenerasi: `cd backend && go run ./cmd/apidoc`
> Verifikasi sinkron: `cd backend && go run ./cmd/apidoc -check`

Total endpoint API: **126** (+1 penyajian berkas statis `GET /uploads/`).

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
| POST | `/v1/auth/unbind-google` | unbindGoogle | bearer | 211 |
| GET | `/v1/auth/google-identity` | googleIdentityStatus | bearer | 212 |
| POST | `/v1/auth/google-token-exchange` | exchangeGoogleToken | bearer | 213 |
| POST | `/v1/auth/complete-professional` | completeProfessionalProfile | bearer | 214 |
| POST | `/v1/auth/refresh` | refresh | publik | 215 |
| POST | `/v1/auth/logout` | logout | publik | 216 |
| POST | `/v1/auth/change-password` | changePassword | bearer | 217 |

## `me`

| Method | Path | Handler | Auth | Baris |
|---|---|---|---|---:|
| GET | `/v1/me` | me | bearer | 218 |
| PATCH | `/v1/me` | updateMe | bearer | 219 |

## `device-tokens`

| Method | Path | Handler | Auth | Baris |
|---|---|---|---|---:|
| POST | `/v1/device-tokens` | upsertDeviceToken | bearer | 220 |

## `screenings`

| Method | Path | Handler | Auth | Baris |
|---|---|---|---|---:|
| POST | `/v1/screenings` | createScreening | bearer | 221 |
| GET | `/v1/screenings` | listScreenings | bearer | 222 |
| POST | `/v1/screenings/{screening_id}/review` | reviewScreening | bearer | 223 |

## `screening-reviews`

| Method | Path | Handler | Auth | Baris |
|---|---|---|---|---:|
| GET | `/v1/screening-reviews` | listScreeningReviews | bearer | 224 |

## `patient-professional-links`

| Method | Path | Handler | Auth | Baris |
|---|---|---|---|---:|
| GET | `/v1/patient-professional-links` | listPatientProfessionalLinks | bearer | 225 |
| POST | `/v1/patient-professional-links` | linkPatientToProfessional | bearer | 226 |

## `professional-notes`

| Method | Path | Handler | Auth | Baris |
|---|---|---|---|---:|
| GET | `/v1/professional-notes` | listProfessionalNotes | bearer | 227 |
| POST | `/v1/professional-notes` | createProfessionalNote | bearer | 228 |

## `follow-ups`

| Method | Path | Handler | Auth | Baris |
|---|---|---|---|---:|
| GET | `/v1/follow-ups` | listFollowUps | bearer | 229 |
| POST | `/v1/follow-ups` | createFollowUp | bearer | 230 |
| PATCH | `/v1/follow-ups/{follow_up_id}/read` | markFollowUpRead | bearer | 231 |

## `mood-checkins`

| Method | Path | Handler | Auth | Baris |
|---|---|---|---|---:|
| GET | `/v1/mood-checkins` | listMoodCheckins | bearer | 232 |
| POST | `/v1/mood-checkins` | createMoodCheckin | bearer | 233 |

## `diary-entries`

| Method | Path | Handler | Auth | Baris |
|---|---|---|---|---:|
| GET | `/v1/diary-entries` | listDiaryEntries | bearer | 234 |
| POST | `/v1/diary-entries` | createDiaryEntry | bearer | 235 |
| PUT | `/v1/diary-entries/{diary_id}` | updateDiaryEntry | bearer | 236 |
| DELETE | `/v1/diary-entries/{diary_id}` | deleteDiaryEntry | bearer | 237 |
| PATCH | `/v1/diary-entries/{diary_id}/feedback` | updateDiaryFeedback | bearer | 238 |

## `medications`

| Method | Path | Handler | Auth | Baris |
|---|---|---|---|---:|
| GET | `/v1/medications` | listMedications | bearer | 239 |
| POST | `/v1/medications` | createMedication | bearer | 240 |
| PUT | `/v1/medications/{medication_id}` | updateMedication | bearer | 244 |
| DELETE | `/v1/medications/{medication_id}` | deleteMedication | bearer | 245 |

## `medication-logs`

| Method | Path | Handler | Auth | Baris |
|---|---|---|---|---:|
| GET | `/v1/medication-logs` | listMedicationLogs | bearer | 246 |
| POST | `/v1/medication-logs` | createMedicationLog | bearer | 247 |

## `timeline`

| Method | Path | Handler | Auth | Baris |
|---|---|---|---|---:|
| GET | `/v1/timeline` | timeline | bearer | 248 |

## `audit-logs`

| Method | Path | Handler | Auth | Baris |
|---|---|---|---|---:|
| GET | `/v1/audit-logs` | auditLogs | bearer | 249 |

## `privacy`

| Method | Path | Handler | Auth | Baris |
|---|---|---|---|---:|
| GET | `/v1/privacy/consents` | getPrivacyConsent | bearer | 250 |
| PUT | `/v1/privacy/consents` | updatePrivacyConsent | bearer | 251 |

## `messages`

| Method | Path | Handler | Auth | Baris |
|---|---|---|---|---:|
| GET | `/v1/messages` | listMessages | bearer | 252 |
| POST | `/v1/messages` | sendMessage | bearer | 253 |

## `notifications`

| Method | Path | Handler | Auth | Baris |
|---|---|---|---|---:|
| GET | `/v1/notifications` | listNotifications | bearer | 254 |
| PATCH | `/v1/notifications/read-all` | markAllNotificationsRead | bearer | 255 |
| PATCH | `/v1/notifications/{notification_id}/read` | markNotificationRead | bearer | 256 |
| POST | `/v1/notifications/test` | testNotification | bearer | 257 |

## `realtime`

| Method | Path | Handler | Auth | Baris |
|---|---|---|---|---:|
| GET | `/v1/realtime/ws` | realtimeWS | bearer (query token) | 258 |

## `emergency-contacts`

| Method | Path | Handler | Auth | Baris |
|---|---|---|---|---:|
| GET | `/v1/emergency-contacts` | listEmergencyContacts | bearer | 260 |
| POST | `/v1/emergency-contacts` | createEmergencyContact | bearer | 261 |
| PUT | `/v1/emergency-contacts/{id}` | updateEmergencyContact | bearer | 262 |
| DELETE | `/v1/emergency-contacts/{id}` | deleteEmergencyContact | bearer | 263 |

## `crisis-alerts`

| Method | Path | Handler | Auth | Baris |
|---|---|---|---|---:|
| POST | `/v1/crisis-alerts` | handleCrisisAlertV2 | bearer | 264 |

## `crisis-incidents`

| Method | Path | Handler | Auth | Baris |
|---|---|---|---|---:|
| GET | `/v1/crisis-incidents` | listCrisisIncidents | bearer | 265 |
| POST | `/v1/crisis-incidents/{id}/resolve` | resolveCrisisIncident | bearer | 266 |

## `sos-blast-status`

| Method | Path | Handler | Auth | Baris |
|---|---|---|---|---:|
| GET | `/v1/sos-blast-status` | listBlastStatus | bearer | 267 |

## `credentials`

| Method | Path | Handler | Auth | Baris |
|---|---|---|---|---:|
| POST | `/v1/credentials` | uploadCredentials | bearer | 269 |
| GET | `/v1/credentials/me` | getMyCredentials | bearer | 270 |

## `upload`

| Method | Path | Handler | Auth | Baris |
|---|---|---|---|---:|
| POST | `/v1/upload` | uploadFile | bearer | 272 |

## `uploads`

| Method | Path | Handler | Auth | Baris |
|---|---|---|---|---:|
| GET | `/uploads/` | uploads (statis) | publik | 274 |

## `psych-tests`

| Method | Path | Handler | Auth | Baris |
|---|---|---|---|---:|
| GET | `/v1/psych-tests` | listPsychTests | publik | 276 |

## `doctors`

| Method | Path | Handler | Auth | Baris |
|---|---|---|---|---:|
| GET | `/v1/doctors/search` | searchDoctors | publik | 279 |
| GET | `/v1/doctors/{user_id}` | getDoctorProfile | publik | 280 |
| GET | `/v1/doctors/{user_id}/slots` | getDoctorAvailableSlots | publik | 281 |
| GET | `/v1/doctors/{user_id}/availability` | getDoctorAvailability | publik | 282 |
| GET | `/v1/doctors/{user_id}/reviews` | listDoctorReviews | publik | 319 |
| POST | `/v1/doctors/{user_id}/reviews` | createDoctorReview | bearer | 320 |

## `pricing`

| Method | Path | Handler | Auth | Baris |
|---|---|---|---|---:|
| GET | `/v1/pricing` | getPricing | bearer | 283 |

## `bookings`

| Method | Path | Handler | Auth | Baris |
|---|---|---|---|---:|
| POST | `/v1/bookings` | createBooking | bearer | 285 |
| POST | `/v1/bookings/{booking_id}/cancel` | cancelPendingBooking | bearer | 286 |
| GET | `/v1/bookings` | listBookings | bearer | 291 |

## `payments`

| Method | Path | Handler | Auth | Baris |
|---|---|---|---|---:|
| POST | `/v1/payments` | createPayment | bearer | 287 |
| POST | `/v1/payments/mark-paid` | markPaymentPaid | bearer | 288 |

## `webhooks`

| Method | Path | Handler | Auth | Baris |
|---|---|---|---|---:|
| POST | `/v1/webhooks/payment` | paymentWebhook | signature | 290 |

## `care-packages`

| Method | Path | Handler | Auth | Baris |
|---|---|---|---|---:|
| POST | `/v1/care-packages` | createCarePackage | bearer | 293 |
| GET | `/v1/care-packages` | listCarePackages | bearer | 294 |
| POST | `/v1/care-packages/{package_id}/cancel` | cancelPendingCarePackage | bearer | 295 |

## `care-sessions`

| Method | Path | Handler | Auth | Baris |
|---|---|---|---|---:|
| POST | `/v1/care-sessions` | scheduleSession | bearer | 296 |
| GET | `/v1/care-sessions` | listCareSessions | bearer | 297 |
| PATCH | `/v1/care-sessions/{session_id}` | updateCareSession | bearer | 298 |
| POST | `/v1/care-sessions/{session_id}/reschedule` | rescheduleCareSession | bearer | 299 |
| POST | `/v1/care-sessions/{session_id}/meet-link` | ensureMeetLinkHandler | bearer | 301 |
| POST | `/v1/care-sessions/{session_id}/refund` | refundCareSession | bearer | 307 |

## `google`

| Method | Path | Handler | Auth | Baris |
|---|---|---|---|---:|
| GET | `/v1/google/status` | googleStatusHandler | bearer | 303 |

## `meet`

| Method | Path | Handler | Auth | Baris |
|---|---|---|---|---:|
| POST | `/v1/meet/quick` | createQuickMeet | bearer | 305 |

## `care-refunds`

| Method | Path | Handler | Auth | Baris |
|---|---|---|---|---:|
| GET | `/v1/care-refunds` | listCareRefunds | bearer | 308 |

## `chat-permission`

| Method | Path | Handler | Auth | Baris |
|---|---|---|---|---:|
| GET | `/v1/chat-permission` | chatPermission | bearer | 309 |

## `professional`

| Method | Path | Handler | Auth | Baris |
|---|---|---|---|---:|
| GET | `/v1/professional/time-off` | listTimeOff | bearer | 311 |
| POST | `/v1/professional/time-off` | addTimeOff | bearer | 312 |
| DELETE | `/v1/professional/time-off/{id}` | deleteTimeOff | bearer | 313 |
| PUT | `/v1/professional/pricing` | updatePricing | bearer | 314 |
| GET | `/v1/professional/schedules` | listMySchedules | bearer | 315 |
| PUT | `/v1/professional/schedules` | updateMySchedules | bearer | 316 |
| DELETE | `/v1/professional/schedules/{id}` | deleteMySchedule | bearer | 318 |

## `earnings`

| Method | Path | Handler | Auth | Baris |
|---|---|---|---|---:|
| GET | `/v1/earnings` | earningsSummary | bearer | 321 |
| POST | `/v1/earnings/payout` | requestPayoutAll | bearer | 323 |
| POST | `/v1/earnings/{earning_id}/payout` | requestPayout | bearer | 324 |

## `e-prescriptions`

| Method | Path | Handler | Auth | Baris |
|---|---|---|---|---:|
| POST | `/v1/e-prescriptions` | createEPrescription | bearer | 325 |
| GET | `/v1/e-prescriptions` | listEPrescriptions | bearer | 326 |
| GET | `/v1/e-prescriptions/{id}` | getEPrescription | bearer | 327 |
| GET | `/v1/e-prescriptions/verify` | verifyEPrescriptionQR | publik | 329 |

## `health-record`

| Method | Path | Handler | Auth | Baris |
|---|---|---|---|---:|
| GET | `/v1/health-record` | getHealthRecord | bearer | 331 |
| PUT | `/v1/health-record` | updateHealthRecord | bearer | 332 |

## `goals`

| Method | Path | Handler | Auth | Baris |
|---|---|---|---|---:|
| GET | `/v1/goals` | listGoals | bearer | 334 |
| POST | `/v1/goals` | createGoal | bearer | 335 |
| PATCH | `/v1/goals/{goal_id}` | updateGoal | bearer | 336 |
| DELETE | `/v1/goals/{goal_id}` | deleteGoal | bearer | 337 |

## `habit-logs`

| Method | Path | Handler | Auth | Baris |
|---|---|---|---|---:|
| GET | `/v1/habit-logs` | listHabitLogs | bearer | 338 |
| POST | `/v1/habit-logs` | logHabit | bearer | 339 |

## `therapy-submissions`

| Method | Path | Handler | Auth | Baris |
|---|---|---|---|---:|
| GET | `/v1/therapy-submissions` | listTherapySubmissions | bearer | 341 |
| POST | `/v1/therapy-submissions` | createTherapySubmission | bearer | 342 |
| GET | `/v1/therapy-submissions/{submission_id}` | getTherapySubmission | bearer | 343 |
| POST | `/v1/therapy-submissions/{submission_id}/share` | shareTherapySubmission | bearer | 344 |
| DELETE | `/v1/therapy-submissions/{submission_id}` | deleteTherapySubmission | bearer | 345 |

## `admin`

| Method | Path | Handler | Auth | Baris |
|---|---|---|---|---:|
| GET | `/v1/admin/users` | listAdminUsers | bearer (admin) | 347 |
| PATCH | `/v1/admin/users/{user_id}` | updateAdminUser | bearer (admin) | 348 |
| DELETE | `/v1/admin/users/{user_id}` | deleteAdminUser | bearer (admin) | 349 |
| GET | `/v1/admin/credentials/pending` | listPendingCredentials | bearer (admin) | 350 |
| POST | `/v1/admin/credentials/{id}/verify` | verifyCredential | bearer (admin) | 351 |
| POST | `/v1/admin/doctors` | createAdminDoctor | bearer (admin) | 352 |
| GET | `/v1/admin/doctors` | listAdminDoctors | bearer (admin) | 353 |
| GET | `/v1/admin/doctors/{user_id}` | getAdminDoctor | bearer (admin) | 354 |
| PUT | `/v1/admin/doctors/{user_id}` | updateAdminDoctor | bearer (admin) | 355 |

