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
| GET | `/` | root | publik | 205 |
| GET | `/healthz` | health | publik | 206 |

## `auth`

| Method | Path | Handler | Auth | Baris |
|---|---|---|---|---:|
| POST | `/v1/auth/register` | register | publik | 207 |
| POST | `/v1/auth/login` | login | publik | 208 |
| POST | `/v1/auth/google` | googleLogin | publik | 209 |
| POST | `/v1/auth/link-google` | linkGoogle | bearer | 210 |
| POST | `/v1/auth/bind-google` | bindGoogle | bearer | 211 |
| POST | `/v1/auth/unbind-google` | unbindGoogle | bearer | 212 |
| GET | `/v1/auth/google-identity` | googleIdentityStatus | bearer | 213 |
| POST | `/v1/auth/google-token-exchange` | exchangeGoogleToken | bearer | 214 |
| POST | `/v1/auth/complete-professional` | completeProfessionalProfile | bearer | 215 |
| POST | `/v1/auth/refresh` | refresh | publik | 216 |
| POST | `/v1/auth/logout` | logout | publik | 217 |
| POST | `/v1/auth/change-password` | changePassword | bearer | 218 |

## `me`

| Method | Path | Handler | Auth | Baris |
|---|---|---|---|---:|
| GET | `/v1/me` | me | bearer | 219 |
| PATCH | `/v1/me` | updateMe | bearer | 220 |

## `device-tokens`

| Method | Path | Handler | Auth | Baris |
|---|---|---|---|---:|
| POST | `/v1/device-tokens` | upsertDeviceToken | bearer | 221 |

## `screenings`

| Method | Path | Handler | Auth | Baris |
|---|---|---|---|---:|
| POST | `/v1/screenings` | createScreening | bearer | 222 |
| GET | `/v1/screenings` | listScreenings | bearer | 223 |
| POST | `/v1/screenings/{screening_id}/review` | reviewScreening | bearer | 224 |

## `screening-reviews`

| Method | Path | Handler | Auth | Baris |
|---|---|---|---|---:|
| GET | `/v1/screening-reviews` | listScreeningReviews | bearer | 225 |

## `patient-professional-links`

| Method | Path | Handler | Auth | Baris |
|---|---|---|---|---:|
| GET | `/v1/patient-professional-links` | listPatientProfessionalLinks | bearer | 226 |
| POST | `/v1/patient-professional-links` | linkPatientToProfessional | bearer | 227 |

## `professional-notes`

| Method | Path | Handler | Auth | Baris |
|---|---|---|---|---:|
| GET | `/v1/professional-notes` | listProfessionalNotes | bearer | 228 |
| POST | `/v1/professional-notes` | createProfessionalNote | bearer | 229 |

## `follow-ups`

| Method | Path | Handler | Auth | Baris |
|---|---|---|---|---:|
| GET | `/v1/follow-ups` | listFollowUps | bearer | 230 |
| POST | `/v1/follow-ups` | createFollowUp | bearer | 231 |
| PATCH | `/v1/follow-ups/{follow_up_id}/read` | markFollowUpRead | bearer | 232 |

## `mood-checkins`

| Method | Path | Handler | Auth | Baris |
|---|---|---|---|---:|
| GET | `/v1/mood-checkins` | listMoodCheckins | bearer | 233 |
| POST | `/v1/mood-checkins` | createMoodCheckin | bearer | 234 |

## `diary-entries`

| Method | Path | Handler | Auth | Baris |
|---|---|---|---|---:|
| GET | `/v1/diary-entries` | listDiaryEntries | bearer | 235 |
| POST | `/v1/diary-entries` | createDiaryEntry | bearer | 236 |
| PUT | `/v1/diary-entries/{diary_id}` | updateDiaryEntry | bearer | 237 |
| DELETE | `/v1/diary-entries/{diary_id}` | deleteDiaryEntry | bearer | 238 |
| PATCH | `/v1/diary-entries/{diary_id}/feedback` | updateDiaryFeedback | bearer | 239 |

## `medications`

| Method | Path | Handler | Auth | Baris |
|---|---|---|---|---:|
| GET | `/v1/medications` | listMedications | bearer | 240 |
| POST | `/v1/medications` | createMedication | bearer | 241 |
| PUT | `/v1/medications/{medication_id}` | updateMedication | bearer | 245 |
| DELETE | `/v1/medications/{medication_id}` | deleteMedication | bearer | 246 |

## `medication-logs`

| Method | Path | Handler | Auth | Baris |
|---|---|---|---|---:|
| GET | `/v1/medication-logs` | listMedicationLogs | bearer | 247 |
| POST | `/v1/medication-logs` | createMedicationLog | bearer | 248 |

## `timeline`

| Method | Path | Handler | Auth | Baris |
|---|---|---|---|---:|
| GET | `/v1/timeline` | timeline | bearer | 249 |

## `audit-logs`

| Method | Path | Handler | Auth | Baris |
|---|---|---|---|---:|
| GET | `/v1/audit-logs` | auditLogs | bearer | 250 |

## `privacy`

| Method | Path | Handler | Auth | Baris |
|---|---|---|---|---:|
| GET | `/v1/privacy/consents` | getPrivacyConsent | bearer | 251 |
| PUT | `/v1/privacy/consents` | updatePrivacyConsent | bearer | 252 |

## `messages`

| Method | Path | Handler | Auth | Baris |
|---|---|---|---|---:|
| GET | `/v1/messages` | listMessages | bearer | 253 |
| POST | `/v1/messages` | sendMessage | bearer | 254 |

## `notifications`

| Method | Path | Handler | Auth | Baris |
|---|---|---|---|---:|
| GET | `/v1/notifications` | listNotifications | bearer | 255 |
| PATCH | `/v1/notifications/read-all` | markAllNotificationsRead | bearer | 256 |
| PATCH | `/v1/notifications/{notification_id}/read` | markNotificationRead | bearer | 257 |
| POST | `/v1/notifications/test` | testNotification | bearer | 258 |

## `realtime`

| Method | Path | Handler | Auth | Baris |
|---|---|---|---|---:|
| GET | `/v1/realtime/ws` | realtimeWS | bearer (query token) | 259 |

## `emergency-contacts`

| Method | Path | Handler | Auth | Baris |
|---|---|---|---|---:|
| GET | `/v1/emergency-contacts` | listEmergencyContacts | bearer | 261 |
| POST | `/v1/emergency-contacts` | createEmergencyContact | bearer | 262 |
| PUT | `/v1/emergency-contacts/{id}` | updateEmergencyContact | bearer | 263 |
| DELETE | `/v1/emergency-contacts/{id}` | deleteEmergencyContact | bearer | 264 |

## `crisis-alerts`

| Method | Path | Handler | Auth | Baris |
|---|---|---|---|---:|
| POST | `/v1/crisis-alerts` | handleCrisisAlertV2 | bearer | 265 |

## `crisis-incidents`

| Method | Path | Handler | Auth | Baris |
|---|---|---|---|---:|
| GET | `/v1/crisis-incidents` | listCrisisIncidents | bearer | 266 |
| POST | `/v1/crisis-incidents/{id}/resolve` | resolveCrisisIncident | bearer | 267 |

## `sos-blast-status`

| Method | Path | Handler | Auth | Baris |
|---|---|---|---|---:|
| GET | `/v1/sos-blast-status` | listBlastStatus | bearer | 268 |

## `credentials`

| Method | Path | Handler | Auth | Baris |
|---|---|---|---|---:|
| POST | `/v1/credentials` | uploadCredentials | bearer | 270 |
| GET | `/v1/credentials/me` | getMyCredentials | bearer | 271 |

## `upload`

| Method | Path | Handler | Auth | Baris |
|---|---|---|---|---:|
| POST | `/v1/upload` | uploadFile | bearer | 273 |

## `uploads`

| Method | Path | Handler | Auth | Baris |
|---|---|---|---|---:|
| GET | `/uploads/` | uploads (statis) | publik | 275 |

## `psych-tests`

| Method | Path | Handler | Auth | Baris |
|---|---|---|---|---:|
| GET | `/v1/psych-tests` | listPsychTests | publik | 277 |

## `doctors`

| Method | Path | Handler | Auth | Baris |
|---|---|---|---|---:|
| GET | `/v1/doctors/search` | searchDoctors | publik | 280 |
| GET | `/v1/doctors/{user_id}` | getDoctorProfile | publik | 281 |
| GET | `/v1/doctors/{user_id}/slots` | getDoctorAvailableSlots | publik | 282 |
| GET | `/v1/doctors/{user_id}/availability` | getDoctorAvailability | publik | 283 |
| GET | `/v1/doctors/{user_id}/reviews` | listDoctorReviews | publik | 320 |
| POST | `/v1/doctors/{user_id}/reviews` | createDoctorReview | bearer | 321 |

## `pricing`

| Method | Path | Handler | Auth | Baris |
|---|---|---|---|---:|
| GET | `/v1/pricing` | getPricing | bearer | 284 |

## `bookings`

| Method | Path | Handler | Auth | Baris |
|---|---|---|---|---:|
| POST | `/v1/bookings` | createBooking | bearer | 286 |
| POST | `/v1/bookings/{booking_id}/cancel` | cancelPendingBooking | bearer | 287 |
| GET | `/v1/bookings` | listBookings | bearer | 292 |

## `payments`

| Method | Path | Handler | Auth | Baris |
|---|---|---|---|---:|
| POST | `/v1/payments` | createPayment | bearer | 288 |
| POST | `/v1/payments/mark-paid` | markPaymentPaid | bearer | 289 |

## `webhooks`

| Method | Path | Handler | Auth | Baris |
|---|---|---|---|---:|
| POST | `/v1/webhooks/payment` | paymentWebhook | signature | 291 |

## `care-packages`

| Method | Path | Handler | Auth | Baris |
|---|---|---|---|---:|
| POST | `/v1/care-packages` | createCarePackage | bearer | 294 |
| GET | `/v1/care-packages` | listCarePackages | bearer | 295 |
| POST | `/v1/care-packages/{package_id}/cancel` | cancelPendingCarePackage | bearer | 296 |

## `care-sessions`

| Method | Path | Handler | Auth | Baris |
|---|---|---|---|---:|
| POST | `/v1/care-sessions` | scheduleSession | bearer | 297 |
| GET | `/v1/care-sessions` | listCareSessions | bearer | 298 |
| PATCH | `/v1/care-sessions/{session_id}` | updateCareSession | bearer | 299 |
| POST | `/v1/care-sessions/{session_id}/reschedule` | rescheduleCareSession | bearer | 300 |
| POST | `/v1/care-sessions/{session_id}/meet-link` | ensureMeetLinkHandler | bearer | 302 |
| POST | `/v1/care-sessions/{session_id}/refund` | refundCareSession | bearer | 308 |

## `google`

| Method | Path | Handler | Auth | Baris |
|---|---|---|---|---:|
| GET | `/v1/google/status` | googleStatusHandler | bearer | 304 |

## `meet`

| Method | Path | Handler | Auth | Baris |
|---|---|---|---|---:|
| POST | `/v1/meet/quick` | createQuickMeet | bearer | 306 |

## `care-refunds`

| Method | Path | Handler | Auth | Baris |
|---|---|---|---|---:|
| GET | `/v1/care-refunds` | listCareRefunds | bearer | 309 |

## `chat-permission`

| Method | Path | Handler | Auth | Baris |
|---|---|---|---|---:|
| GET | `/v1/chat-permission` | chatPermission | bearer | 310 |

## `professional`

| Method | Path | Handler | Auth | Baris |
|---|---|---|---|---:|
| GET | `/v1/professional/time-off` | listTimeOff | bearer | 312 |
| POST | `/v1/professional/time-off` | addTimeOff | bearer | 313 |
| DELETE | `/v1/professional/time-off/{id}` | deleteTimeOff | bearer | 314 |
| PUT | `/v1/professional/pricing` | updatePricing | bearer | 315 |
| GET | `/v1/professional/schedules` | listMySchedules | bearer | 316 |
| PUT | `/v1/professional/schedules` | updateMySchedules | bearer | 317 |
| DELETE | `/v1/professional/schedules/{id}` | deleteMySchedule | bearer | 319 |

## `earnings`

| Method | Path | Handler | Auth | Baris |
|---|---|---|---|---:|
| GET | `/v1/earnings` | earningsSummary | bearer | 322 |
| POST | `/v1/earnings/payout` | requestPayoutAll | bearer | 324 |
| POST | `/v1/earnings/{earning_id}/payout` | requestPayout | bearer | 325 |

## `e-prescriptions`

| Method | Path | Handler | Auth | Baris |
|---|---|---|---|---:|
| POST | `/v1/e-prescriptions` | createEPrescription | bearer | 326 |
| GET | `/v1/e-prescriptions` | listEPrescriptions | bearer | 327 |
| GET | `/v1/e-prescriptions/{id}` | getEPrescription | bearer | 328 |
| GET | `/v1/e-prescriptions/verify` | verifyEPrescriptionQR | publik | 330 |

## `health-record`

| Method | Path | Handler | Auth | Baris |
|---|---|---|---|---:|
| GET | `/v1/health-record` | getHealthRecord | bearer | 332 |
| PUT | `/v1/health-record` | updateHealthRecord | bearer | 333 |

## `goals`

| Method | Path | Handler | Auth | Baris |
|---|---|---|---|---:|
| GET | `/v1/goals` | listGoals | bearer | 335 |
| POST | `/v1/goals` | createGoal | bearer | 336 |
| PATCH | `/v1/goals/{goal_id}` | updateGoal | bearer | 337 |
| DELETE | `/v1/goals/{goal_id}` | deleteGoal | bearer | 338 |

## `habit-logs`

| Method | Path | Handler | Auth | Baris |
|---|---|---|---|---:|
| GET | `/v1/habit-logs` | listHabitLogs | bearer | 339 |
| POST | `/v1/habit-logs` | logHabit | bearer | 340 |

## `therapy-submissions`

| Method | Path | Handler | Auth | Baris |
|---|---|---|---|---:|
| GET | `/v1/therapy-submissions` | listTherapySubmissions | bearer | 342 |
| POST | `/v1/therapy-submissions` | createTherapySubmission | bearer | 343 |
| GET | `/v1/therapy-submissions/{submission_id}` | getTherapySubmission | bearer | 344 |
| POST | `/v1/therapy-submissions/{submission_id}/share` | shareTherapySubmission | bearer | 345 |
| DELETE | `/v1/therapy-submissions/{submission_id}` | deleteTherapySubmission | bearer | 346 |

## `admin`

| Method | Path | Handler | Auth | Baris |
|---|---|---|---|---:|
| GET | `/v1/admin/users` | listAdminUsers | bearer (admin) | 348 |
| PATCH | `/v1/admin/users/{user_id}` | updateAdminUser | bearer (admin) | 349 |
| DELETE | `/v1/admin/users/{user_id}` | deleteAdminUser | bearer (admin) | 350 |
| GET | `/v1/admin/credentials/pending` | listPendingCredentials | bearer (admin) | 351 |
| POST | `/v1/admin/credentials/{id}/verify` | verifyCredential | bearer (admin) | 352 |
| POST | `/v1/admin/doctors` | createAdminDoctor | bearer (admin) | 353 |
| GET | `/v1/admin/doctors` | listAdminDoctors | bearer (admin) | 354 |
| GET | `/v1/admin/doctors/{user_id}` | getAdminDoctor | bearer (admin) | 355 |
| PUT | `/v1/admin/doctors/{user_id}` | updateAdminDoctor | bearer (admin) | 356 |

