package main

import (
	"context"
	"database/sql"
	"encoding/json"
	"fmt"
	"log/slog"
	"net/http"
	"os"
	"os/signal"
	"syscall"
	"time"

	_ "github.com/jackc/pgx/v5/stdlib"
)

type AdminServer struct {
	db     *sql.DB
	logger *slog.Logger
}

type DashboardStats struct {
	TotalUsers         int            `json:"total_users"`
	TotalPatients      int            `json:"total_patients"`
	TotalProfessionals int            `json:"total_professionals"`
	TotalScreenings    int            `json:"total_screenings"`
	TotalMoodCheckins  int            `json:"total_mood_checkins"`
	TotalDiaryEntries  int            `json:"total_diary_entries"`
	TotalMedications   int            `json:"total_medications"`
	TotalNotifications int            `json:"total_notifications"`
	ActiveSessions     int            `json:"active_sessions"`
	RecentActivity     []ActivityItem `json:"recent_activity"`
	SystemHealth       SystemHealth   `json:"system_health"`
}

type ActivityItem struct {
	Type      string    `json:"type"`
	UserID    string    `json:"user_id"`
	Action    string    `json:"action"`
	Timestamp time.Time `json:"timestamp"`
}

type SystemHealth struct {
	DatabaseStatus string  `json:"database_status"`
	Uptime         string  `json:"uptime"`
	MemoryUsage    float64 `json:"memory_usage"`
	CPUUsage       float64 `json:"cpu_usage"`
}

func main() {
	logger := slog.New(slog.NewJSONHandler(os.Stdout, &slog.HandlerOptions{Level: slog.LevelInfo}))

	dbURL := os.Getenv("MALVA_DATABASE_URL")
	if dbURL == "" {
		dbURL = "postgres://malva:malva_dev_password@localhost:5432/malva?sslmode=disable"
	}

	db, err := sql.Open("pgx", dbURL)
	if err != nil {
		logger.Error("failed to connect to database", "error", err)
		os.Exit(1)
	}
	defer db.Close()

	db.SetMaxOpenConns(10)
	db.SetMaxIdleConns(5)
	db.SetConnMaxLifetime(30 * time.Minute)

	ctx, stop := signal.NotifyContext(context.Background(), os.Interrupt, syscall.SIGTERM)
	defer stop()

	pingCtx, cancelPing := context.WithTimeout(ctx, 5*time.Second)
	defer cancelPing()
	if err := db.PingContext(pingCtx); err != nil {
		logger.Error("failed to ping database", "error", err)
		os.Exit(1)
	}

	server := &AdminServer{
		db:     db,
		logger: logger,
	}

	mux := http.NewServeMux()
	mux.HandleFunc("GET /", server.dashboardHTML)
	mux.HandleFunc("GET /api/stats", server.getStats)
	mux.HandleFunc("GET /api/users", server.listUsers)
	mux.HandleFunc("GET /api/screenings", server.listScreenings)
	mux.HandleFunc("GET /api/activity", server.recentActivity)
	mux.HandleFunc("GET /api/health", server.healthCheck)

	httpServer := &http.Server{
		Addr:              ":8081",
		Handler:           corsMiddleware(securityHeadersMiddleware(mux)),
		ReadHeaderTimeout: 10 * time.Second,
	}

	errCh := make(chan error, 1)
	go func() {
		logger.Info("admin dashboard listening", "addr", ":8081")
		if err := httpServer.ListenAndServe(); err != nil && err != http.ErrServerClosed {
			errCh <- err
			return
		}
		errCh <- nil
	}()

	select {
	case <-ctx.Done():
		shutdownCtx, cancelShutdown := context.WithTimeout(context.Background(), 10*time.Second)
		defer cancelShutdown()
		httpServer.Shutdown(shutdownCtx)
	case err := <-errCh:
		if err != nil {
			logger.Error("server error", "error", err)
		}
	}
}

func (s *AdminServer) dashboardHTML(w http.ResponseWriter, r *http.Request) {
	w.Header().Set("Content-Type", "text/html; charset=utf-8")
	w.WriteHeader(http.StatusOK)
	fmt.Fprint(w, adminDashboardHTML)
}

func (s *AdminServer) getStats(w http.ResponseWriter, r *http.Request) {
	ctx := r.Context()
	stats := DashboardStats{}

	s.db.QueryRowContext(ctx, "SELECT COUNT(*) FROM users WHERE disabled_at IS NULL").Scan(&stats.TotalUsers)
	s.db.QueryRowContext(ctx, "SELECT COUNT(*) FROM users WHERE role = 'patient' AND disabled_at IS NULL").Scan(&stats.TotalPatients)
	s.db.QueryRowContext(ctx, "SELECT COUNT(*) FROM users WHERE role = 'professional' AND disabled_at IS NULL").Scan(&stats.TotalProfessionals)
	s.db.QueryRowContext(ctx, "SELECT COUNT(*) FROM screening_sessions").Scan(&stats.TotalScreenings)
	s.db.QueryRowContext(ctx, "SELECT COUNT(*) FROM mood_checkins").Scan(&stats.TotalMoodCheckins)
	s.db.QueryRowContext(ctx, "SELECT COUNT(*) FROM diary_entries").Scan(&stats.TotalDiaryEntries)
	s.db.QueryRowContext(ctx, "SELECT COUNT(*) FROM medications").Scan(&stats.TotalMedications)
	s.db.QueryRowContext(ctx, "SELECT COUNT(*) FROM notifications").Scan(&stats.TotalNotifications)

	stats.SystemHealth = SystemHealth{
		DatabaseStatus: "connected",
		Uptime:         time.Since(startTime).String(),
	}

	writeJSON(w, stats)
}

func (s *AdminServer) listUsers(w http.ResponseWriter, r *http.Request) {
	ctx := r.Context()
	rows, err := s.db.QueryContext(ctx, `
		SELECT id, email, role::text, display_name, created_at
		FROM users
		WHERE disabled_at IS NULL
		ORDER BY created_at DESC
		LIMIT 100
	`)
	if err != nil {
		http.Error(w, err.Error(), http.StatusInternalServerError)
		return
	}
	defer rows.Close()

	type User struct {
		ID          string    `json:"id"`
		Email       string    `json:"email"`
		Role        string    `json:"role"`
		DisplayName string    `json:"display_name"`
		CreatedAt   time.Time `json:"created_at"`
	}

	var users []User
	for rows.Next() {
		var u User
		if err := rows.Scan(&u.ID, &u.Email, &u.Role, &u.DisplayName, &u.CreatedAt); err != nil {
			continue
		}
		users = append(users, u)
	}

	writeJSON(w, map[string]any{"users": users})
}

func (s *AdminServer) listScreenings(w http.ResponseWriter, r *http.Request) {
	ctx := r.Context()
	rows, err := s.db.QueryContext(ctx, `
		SELECT id, patient_id, overall_level::text, crisis_flag, created_at
		FROM screening_sessions
		ORDER BY created_at DESC
		LIMIT 50
	`)
	if err != nil {
		http.Error(w, err.Error(), http.StatusInternalServerError)
		return
	}
	defer rows.Close()

	type Screening struct {
		ID           string    `json:"id"`
		PatientID    string    `json:"patient_id"`
		OverallLevel string    `json:"overall_level"`
		CrisisFlag   bool      `json:"crisis_flag"`
		CreatedAt    time.Time `json:"created_at"`
	}

	var screenings []Screening
	for rows.Next() {
		var s Screening
		if err := rows.Scan(&s.ID, &s.PatientID, &s.OverallLevel, &s.CrisisFlag, &s.CreatedAt); err != nil {
			continue
		}
		screenings = append(screenings, s)
	}

	writeJSON(w, map[string]any{"screenings": screenings})
}

func (s *AdminServer) recentActivity(w http.ResponseWriter, r *http.Request) {
	ctx := r.Context()
	rows, err := s.db.QueryContext(ctx, `
		SELECT action, user_id, target_type, created_at
		FROM audit_logs
		ORDER BY created_at DESC
		LIMIT 50
	`)
	if err != nil {
		http.Error(w, err.Error(), http.StatusInternalServerError)
		return
	}
	defer rows.Close()

	var activities []ActivityItem
	for rows.Next() {
		var a ActivityItem
		if err := rows.Scan(&a.Action, &a.UserID, &a.Type, &a.Timestamp); err != nil {
			continue
		}
		activities = append(activities, a)
	}

	writeJSON(w, map[string]any{"activities": activities})
}

func (s *AdminServer) healthCheck(w http.ResponseWriter, r *http.Request) {
	ctx, cancel := context.WithTimeout(r.Context(), 2*time.Second)
	defer cancel()

	dbStatus := "connected"
	if err := s.db.PingContext(ctx); err != nil {
		dbStatus = "disconnected"
	}

	writeJSON(w, map[string]any{
		"status":   "ok",
		"database": dbStatus,
		"uptime":   time.Since(startTime).String(),
		"timestamp": time.Now().UTC(),
	})
}

var startTime = time.Now()

func writeJSON(w http.ResponseWriter, value any) {
	w.Header().Set("Content-Type", "application/json")
	json.NewEncoder(w).Encode(value)
}

func corsMiddleware(next http.Handler) http.Handler {
	return http.HandlerFunc(func(w http.ResponseWriter, r *http.Request) {
		w.Header().Set("Access-Control-Allow-Origin", "*")
		w.Header().Set("Access-Control-Allow-Methods", "GET, OPTIONS")
		w.Header().Set("Access-Control-Allow-Headers", "Content-Type, Authorization")
		if r.Method == http.MethodOptions {
			w.WriteHeader(http.StatusNoContent)
			return
		}
		next.ServeHTTP(w, r)
	})
}

func securityHeadersMiddleware(next http.Handler) http.Handler {
	return http.HandlerFunc(func(w http.ResponseWriter, r *http.Request) {
		w.Header().Set("X-Content-Type-Options", "nosniff")
		w.Header().Set("X-Frame-Options", "DENY")
		w.Header().Set("Referrer-Policy", "no-referrer")
		next.ServeHTTP(w, r)
	})
}

const adminDashboardHTML = `<!DOCTYPE html>
<html lang="en">
<head>
  <meta charset="UTF-8">
  <meta name="viewport" content="width=device-width, initial-scale=1.0">
  <title>Malva Admin Dashboard</title>
  <style>
    * { margin: 0; padding: 0; box-sizing: border-box; }
    body { font-family: -apple-system, BlinkMacSystemFont, 'Segoe UI', Roboto, sans-serif; background: #f5f5f5; color: #333; }
    .header { background: #1a1a2e; color: white; padding: 20px 30px; }
    .header h1 { font-size: 24px; font-weight: 600; }
    .header p { opacity: 0.8; margin-top: 5px; }
    .container { max-width: 1200px; margin: 0 auto; padding: 20px; }
    .stats-grid { display: grid; grid-template-columns: repeat(auto-fit, minmax(200px, 1fr)); gap: 15px; margin-bottom: 30px; }
    .stat-card { background: white; border-radius: 10px; padding: 20px; box-shadow: 0 2px 10px rgba(0,0,0,0.05); }
    .stat-card h3 { font-size: 14px; color: #666; text-transform: uppercase; letter-spacing: 0.5px; }
    .stat-card .value { font-size: 32px; font-weight: 700; color: #1a1a2e; margin-top: 10px; }
    .stat-card .change { font-size: 12px; color: #4caf50; margin-top: 5px; }
    .section { background: white; border-radius: 10px; padding: 20px; box-shadow: 0 2px 10px rgba(0,0,0,0.05); margin-bottom: 20px; }
    .section h2 { font-size: 18px; font-weight: 600; margin-bottom: 15px; color: #1a1a2e; }
    table { width: 100%; border-collapse: collapse; }
    th, td { padding: 12px 15px; text-align: left; border-bottom: 1px solid #eee; }
    th { font-weight: 600; color: #666; font-size: 12px; text-transform: uppercase; }
    tr:hover { background: #f9f9f9; }
    .badge { padding: 4px 8px; border-radius: 12px; font-size: 11px; font-weight: 600; }
    .badge-green { background: #e8f5e9; color: #2e7d32; }
    .badge-red { background: #ffebee; color: #c62828; }
    .badge-yellow { background: #fff3e0; color: #ef6c00; }
    .health-status { display: flex; align-items: center; gap: 10px; }
    .health-dot { width: 10px; height: 10px; border-radius: 50%; background: #4caf50; }
    .health-dot.warning { background: #ff9800; }
    .health-dot.error { background: #f44336; }
    .refresh-btn { background: #1a1a2e; color: white; border: none; padding: 8px 16px; border-radius: 6px; cursor: pointer; font-size: 14px; }
    .refresh-btn:hover { background: #16213e; }
    @media (max-width: 768px) {
      .stats-grid { grid-template-columns: repeat(2, 1fr); }
      .container { padding: 10px; }
    }
  </style>
</head>
<body>
  <div class="header">
    <h1>Malva Admin Dashboard</h1>
    <p>Real-time monitoring and analytics</p>
  </div>
  <div class="container">
    <div style="display: flex; justify-content: space-between; align-items: center; margin-bottom: 20px;">
      <div class="health-status">
        <div class="health-dot" id="healthDot"></div>
        <span id="healthText">System Healthy</span>
      </div>
      <button class="refresh-btn" onclick="refreshData()">Refresh Data</button>
    </div>

    <div class="stats-grid">
      <div class="stat-card">
        <h3>Total Users</h3>
        <div class="value" id="totalUsers">-</div>
      </div>
      <div class="stat-card">
        <h3>Patients</h3>
        <div class="value" id="totalPatients">-</div>
      </div>
      <div class="stat-card">
        <h3>Professionals</h3>
        <div class="value" id="totalProfessionals">-</div>
      </div>
      <div class="stat-card">
        <h3>Screenings</h3>
        <div class="value" id="totalScreenings">-</div>
      </div>
      <div class="stat-card">
        <h3>Mood Check-ins</h3>
        <div class="value" id="totalMoodCheckins">-</div>
      </div>
      <div class="stat-card">
        <h3>Diary Entries</h3>
        <div class="value" id="totalDiaryEntries">-</div>
      </div>
    </div>

    <div class="section">
      <h2>Recent Activity</h2>
      <table>
        <thead>
          <tr>
            <th>Action</th>
            <th>User ID</th>
            <th>Type</th>
            <th>Time</th>
          </tr>
        </thead>
        <tbody id="activityTable">
          <tr><td colspan="4">Loading...</td></tr>
        </tbody>
      </table>
    </div>

    <div class="section">
      <h2>Recent Screenings</h2>
      <table>
        <thead>
          <tr>
            <th>ID</th>
            <th>Patient</th>
            <th>Level</th>
            <th>Crisis</th>
            <th>Time</th>
          </tr>
        </thead>
        <tbody id="screeningsTable">
          <tr><td colspan="5">Loading...</td></tr>
        </tbody>
      </table>
    </div>
  </div>

  <script>
    const API_BASE = window.location.origin;

    async function fetchStats() {
      try {
        const res = await fetch(API_BASE + '/api/stats');
        const data = await res.json();
        document.getElementById('totalUsers').textContent = data.total_users || 0;
        document.getElementById('totalPatients').textContent = data.total_patients || 0;
        document.getElementById('totalProfessionals').textContent = data.total_professionals || 0;
        document.getElementById('totalScreenings').textContent = data.total_screenings || 0;
        document.getElementById('totalMoodCheckins').textContent = data.total_mood_checkins || 0;
        document.getElementById('totalDiaryEntries').textContent = data.total_diary_entries || 0;
      } catch (e) {
        console.error('Failed to fetch stats:', e);
      }
    }

    async function fetchActivity() {
      try {
        const res = await fetch(API_BASE + '/api/activity');
        const data = await res.json();
        const tbody = document.getElementById('activityTable');
        if (data.activities && data.activities.length > 0) {
          tbody.innerHTML = data.activities.slice(0, 10).map(a => '<tr><td>' + a.action + '</td><td>' + a.user_id + '</td><td>' + a.type + '</td><td>' + new Date(a.timestamp).toLocaleString() + '</td></tr>').join('');
        } else {
          tbody.innerHTML = '<tr><td colspan="4">No recent activity</td></tr>';
        }
      } catch (e) {
        console.error('Failed to fetch activity:', e);
      }
    }

    async function fetchScreenings() {
      try {
        const res = await fetch(API_BASE + '/api/screenings');
        const data = await res.json();
        const tbody = document.getElementById('screeningsTable');
        if (data.screenings && data.screenings.length > 0) {
          tbody.innerHTML = data.screenings.slice(0, 10).map(s => '<tr><td>' + s.id.substring(0, 8) + '...</td><td>' + s.patient_id.substring(0, 8) + '...</td><td><span class="badge badge-' + (s.overall_level === 'crisis' ? 'red' : s.overall_level === 'high' ? 'yellow' : 'green') + '">' + s.overall_level + '</span></td><td>' + (s.crisis_flag ? '<span class="badge badge-red">Yes</span>' : '<span class="badge badge-green">No</span>') + '</td><td>' + new Date(s.created_at).toLocaleString() + '</td></tr>').join('');
        } else {
          tbody.innerHTML = '<tr><td colspan="5">No screenings yet</td></tr>';
        }
      } catch (e) {
        console.error('Failed to fetch screenings:', e);
      }
    }

    async function checkHealth() {
      try {
        const res = await fetch(API_BASE + '/api/health');
        const data = await res.json();
        const dot = document.getElementById('healthDot');
        const text = document.getElementById('healthText');
        if (data.database === 'connected') {
          dot.className = 'health-dot';
          text.textContent = 'System Healthy';
        } else {
          dot.className = 'health-dot warning';
          text.textContent = 'Database Disconnected';
        }
      } catch (e) {
        document.getElementById('healthDot').className = 'health-dot error';
        document.getElementById('healthText').textContent = 'System Error';
      }
    }

    function refreshData() {
      fetchStats();
      fetchActivity();
      fetchScreenings();
      checkHealth();
    }

    refreshData();
    setInterval(refreshData, 30000);
  </script>
</body>
</html>`
