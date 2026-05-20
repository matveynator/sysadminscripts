// autopostgresqlbackup.go
//
// Go rewrite of the legacy autopostgresqlbackup bash script.
// It keeps the same backup model: daily, weekly, monthly, per-database directories,
// simple rotation, optional compression, optional pre/post commands and log email.
//
// Build:
//   go build -o autopostgresqlbackup autopostgresqlbackup.go
//
// Install:
//   sudo install -m 0755 autopostgresqlbackup /usr/local/bin/autopostgresqlbackup
//
// PostgreSQL password:
//   Use ~/.pgpass for the user that runs this program.

package main

import (
	"bufio"
	"bytes"
	"compress/gzip"
	"errors"
	"fmt"
	"io"
	"os"
	"os/exec"
	"path/filepath"
	"strconv"
	"strings"
	"time"
)

type Config struct {
	Username        string
	DBHost          string
	DBNames         string
	BackupDir       string
	MailContent     string // log, files, stdout
	MaxAttachmentKB int
	MailAddr        string

	MonthlyDBNames string
	DBExclude      string
	CreateDatabase bool
	SeparateDirs   bool
	DoWeekly       int    // 1..7, Monday..Sunday
	Compression    string // gzip, bzip2, none

	PreBackup  string
	PostBackup string
}

type Runtime struct {
	cfg         Config
	now         time.Time
	date        string
	dayName     string
	dayNumber   int
	dayOfMonth  string
	monthName   string
	weekNumber  int
	dbHostLabel string
	hostArg     []string
	logFile     string
	log         *os.File
	backupFiles []string
}

func main() {
	cfg := defaultConfig()

	rt, err := newRuntime(cfg)
	if err != nil {
		fmt.Fprintln(os.Stderr, err)
		os.Exit(1)
	}
	defer rt.cleanupLog()

	if err := rt.run(); err != nil {
		rt.printf("ERROR: %v\n", err)
		_ = rt.finishOutput()
		rt.sendReport()
		os.Exit(1)
	}

	if err := rt.finishOutput(); err != nil {
		fmt.Fprintln(os.Stderr, err)
		os.Exit(1)
	}
	rt.sendReport()
}

func defaultConfig() Config {
	return Config{
		Username:        "allstars",
		DBHost:          "localhost",
		DBNames:         "all",
		BackupDir:       "/backup/postgres",
		MailContent:     "log",
		MaxAttachmentKB: 4000,
		MailAddr:        "root",

		MonthlyDBNames: "template1 all",
		DBExclude:      "",
		CreateDatabase: true,
		SeparateDirs:   true,
		DoWeekly:       6,
		Compression:    "gzip",

		PreBackup:  "",
		PostBackup: "",
	}
}

func newRuntime(cfg Config) (*Runtime, error) {
	now := time.Now()
	if err := ensureDirs(
		cfg.BackupDir,
		filepath.Join(cfg.BackupDir, "daily"),
		filepath.Join(cfg.BackupDir, "weekly"),
		filepath.Join(cfg.BackupDir, "monthly"),
	); err != nil {
		return nil, err
	}

	hostLabel := cfg.DBHost
	hostArg := []string{}
	if cfg.DBHost == "localhost" {
		if fqdn, err := os.Hostname(); err == nil && fqdn != "" {
			hostLabel = fqdn
		}
	} else {
		hostArg = []string{"-h", cfg.DBHost}
	}

	logFile := filepath.Join(cfg.BackupDir, fmt.Sprintf("%s-%d.log", hostLabel, now.UnixNano()))
	log, err := os.Create(logFile)
	if err != nil {
		return nil, err
	}

	_, week := now.ISOWeek()

	return &Runtime{
		cfg:         cfg,
		now:         now,
		date:        now.Format("2006-01-02"),
		dayName:     now.Weekday().String(),
		dayNumber:   isoWeekday(now),
		dayOfMonth:  now.Format("02"),
		monthName:   now.Month().String(),
		weekNumber:  week,
		dbHostLabel: hostLabel,
		hostArg:     hostArg,
		logFile:     logFile,
		log:         log,
	}, nil
}

func (rt *Runtime) run() error {
	if rt.cfg.PreBackup != "" {
		rt.printSection("Prebackup command output.")
		if err := rt.runShell(rt.cfg.PreBackup); err != nil {
			rt.printf("Prebackup failed: %v\n", err)
		}
		rt.printLine()
	}

	dbNames, monthlyNames, err := rt.resolveDBNames()
	if err != nil {
		return err
	}

	rt.printHeader()

	if rt.cfg.SeparateDirs {
		return rt.runSeparateBackups(dbNames, monthlyNames)
	}
	return rt.runSingleFileBackups(dbNames, monthlyNames)
}

func (rt *Runtime) runSeparateBackups(dbNames, monthlyNames []string) error {
	rt.printf("Backup Start Time %s\n", time.Now().Format(time.RFC1123))
	rt.printLine()

	if rt.dayOfMonth == "01" {
		for _, db := range monthlyNames {
			db = decodeDBName(db)
			dir := filepath.Join(rt.cfg.BackupDir, "monthly", db)
			if err := ensureDirs(dir); err != nil {
				return err
			}

			rt.printf("Monthly Backup of %s...\n", db)
			out := filepath.Join(dir, fmt.Sprintf("%s_%s.%s.%s.sql", db, rt.date, rt.monthName, db))
			if err := rt.dumpDB(db, out); err != nil {
				return err
			}
			finalPath, err := rt.compress(out)
			if err != nil {
				return err
			}
			rt.backupFiles = append(rt.backupFiles, finalPath)
			rt.printDash()
		}
	}

	for _, db := range dbNames {
		db = decodeDBName(db)

		dailyDir := filepath.Join(rt.cfg.BackupDir, "daily", db)
		weeklyDir := filepath.Join(rt.cfg.BackupDir, "weekly", db)
		if err := ensureDirs(dailyDir, weeklyDir); err != nil {
			return err
		}

		if rt.dayNumber == rt.cfg.DoWeekly {
			rt.printf("Weekly Backup of Database ( %s )\n", db)
			rt.printf("Rotating 5 weeks Backups...\n")
			removeWeek := rotatedWeek(rt.weekNumber)
			if err := removeGlob(filepath.Join(weeklyDir, fmt.Sprintf("week.%02d.*", removeWeek))); err != nil {
				return err
			}
			rt.printBlank()

			out := filepath.Join(weeklyDir, fmt.Sprintf("%s_week.%02d.%s.sql", db, rt.weekNumber, rt.date))
			if err := rt.dumpDB(db, out); err != nil {
				return err
			}
			finalPath, err := rt.compress(out)
			if err != nil {
				return err
			}
			rt.backupFiles = append(rt.backupFiles, finalPath)
			rt.printDash()
		} else {
			rt.printf("Daily Backup of Database ( %s )\n", db)
			rt.printf("Rotating last weeks Backup...\n")
			if err := removeGlob(filepath.Join(dailyDir, fmt.Sprintf("*.%s.sql.*", rt.dayName))); err != nil {
				return err
			}
			rt.printBlank()

			out := filepath.Join(dailyDir, fmt.Sprintf("%s_%s.%s.sql", db, rt.date, rt.dayName))
			if err := rt.dumpDB(db, out); err != nil {
				return err
			}
			finalPath, err := rt.compress(out)
			if err != nil {
				return err
			}
			rt.backupFiles = append(rt.backupFiles, finalPath)
			rt.printDash()
		}
	}

	rt.printf("Backup End %s\n", time.Now().Format(time.RFC1123))
	rt.printLine()
	rt.diskUsage()

	if rt.cfg.PostBackup != "" {
		rt.printSection("Postbackup command output.")
		if err := rt.runShell(rt.cfg.PostBackup); err != nil {
			rt.printf("Postbackup failed: %v\n", err)
		}
		rt.printLine()
	}

	return nil
}

func (rt *Runtime) runSingleFileBackups(dbNames, monthlyNames []string) error {
	rt.printf("Backup Start %s\n", time.Now().Format(time.RFC1123))
	rt.printLine()

	if rt.dayOfMonth == "01" {
		rt.printf("Monthly full Backup of ( %s )...\n", strings.Join(monthlyNames, " "))
		out := filepath.Join(rt.cfg.BackupDir, "monthly", fmt.Sprintf("%s.%s.all-databases.sql", rt.date, rt.monthName))
		if err := rt.dumpMany(monthlyNames, out); err != nil {
			return err
		}
		finalPath, err := rt.compress(out)
		if err != nil {
			return err
		}
		rt.backupFiles = append(rt.backupFiles, finalPath)
		rt.printDash()
	}

	if rt.dayNumber == rt.cfg.DoWeekly {
		rt.printf("Weekly Backup of Databases ( %s )\n", strings.Join(dbNames, " "))
		rt.printBlank()
		rt.printf("Rotating 5 weeks Backups...\n")
		removeWeek := rotatedWeek(rt.weekNumber)
		if err := removeGlob(filepath.Join(rt.cfg.BackupDir, "weekly", fmt.Sprintf("week.%02d.*", removeWeek))); err != nil {
			return err
		}
		rt.printBlank()

		out := filepath.Join(rt.cfg.BackupDir, "weekly", fmt.Sprintf("week.%02d.%s.sql", rt.weekNumber, rt.date))
		if err := rt.dumpMany(dbNames, out); err != nil {
			return err
		}
		finalPath, err := rt.compress(out)
		if err != nil {
			return err
		}
		rt.backupFiles = append(rt.backupFiles, finalPath)
		rt.printDash()
	} else {
		rt.printf("Daily Backup of Databases ( %s )\n", strings.Join(dbNames, " "))
		rt.printBlank()
		rt.printf("Rotating last weeks Backup...\n")
		if err := removeGlob(filepath.Join(rt.cfg.BackupDir, "daily", fmt.Sprintf("*.%s.sql.*", rt.dayName))); err != nil {
			return err
		}
		rt.printBlank()

		out := filepath.Join(rt.cfg.BackupDir, "daily", fmt.Sprintf("%s.%s.sql", rt.date, rt.dayName))
		if err := rt.dumpMany(dbNames, out); err != nil {
			return err
		}
		finalPath, err := rt.compress(out)
		if err != nil {
			return err
		}
		rt.backupFiles = append(rt.backupFiles, finalPath)
		rt.printDash()
	}

	rt.printf("Backup End Time %s\n", time.Now().Format(time.RFC1123))
	rt.printLine()
	rt.diskUsage()

	if rt.cfg.PostBackup != "" {
		rt.printSection("Postbackup command output.")
		if err := rt.runShell(rt.cfg.PostBackup); err != nil {
			rt.printf("Postbackup failed: %v\n", err)
		}
		rt.printLine()
	}

	return nil
}

func (rt *Runtime) resolveDBNames() ([]string, []string, error) {
	dbNames := splitWords(rt.cfg.DBNames)
	monthlyNames := splitWords(strings.ReplaceAll(rt.cfg.MonthlyDBNames, "all", rt.cfg.DBNames))

	if rt.cfg.DBNames == "all" {
		all, err := rt.listDatabases()
		if err != nil {
			return nil, nil, err
		}

		exclude := map[string]bool{}
		for _, db := range splitWords(rt.cfg.DBExclude) {
			exclude[db] = true
		}

		dbNames = dbNames[:0]
		for _, db := range all {
			if !exclude[db] {
				dbNames = append(dbNames, db)
			}
		}
		monthlyNames = append([]string{}, dbNames...)
	}

	if len(dbNames) == 0 {
		return nil, nil, errors.New("no databases selected for backup")
	}
	if len(monthlyNames) == 0 {
		monthlyNames = append([]string{}, dbNames...)
	}

	return dbNames, monthlyNames, nil
}

func (rt *Runtime) listDatabases() ([]string, error) {
	args := []string{"-U", rt.cfg.Username}
	args = append(args, rt.hostArg...)
	args = append(args, "-l", "-A", "-F:")

	cmd := exec.Command("psql", args...)
	out, err := cmd.Output()
	if err != nil {
		if ee, ok := err.(*exec.ExitError); ok {
			return nil, fmt.Errorf("psql database list failed: %s", strings.TrimSpace(string(ee.Stderr)))
		}
		return nil, err
	}

	var dbs []string
	sc := bufio.NewScanner(bytes.NewReader(out))
	for sc.Scan() {
		line := sc.Text()
		if !strings.Contains(line, ":") {
			continue
		}
		if strings.Contains(line, "Name:Owner") {
			continue
		}
		name := strings.SplitN(line, ":", 2)[0]
		if name == "" || name == "template0" {
			continue
		}
		dbs = append(dbs, name)
	}
	return dbs, sc.Err()
}

func (rt *Runtime) dumpDB(db, outputPath string) error {
	args := []string{"--username=" + rt.cfg.Username}
	args = append(args, rt.hostArg...)
	if rt.cfg.SeparateDirs && rt.cfg.CreateDatabase {
		args = append(args, "--create")
	}
	args = append(args, db)

	return rt.runToFile("pg_dump", args, outputPath)
}

func (rt *Runtime) dumpMany(dbs []string, outputPath string) error {
	if len(dbs) == 1 && dbs[0] != "all" {
		return rt.dumpDB(decodeDBName(dbs[0]), outputPath)
	}

	out, err := os.Create(outputPath)
	if err != nil {
		return err
	}
	defer out.Close()

	for _, db := range dbs {
		db = decodeDBName(db)
		rt.printf("Dumping database %s into combined file...\n", db)

		args := []string{"--username=" + rt.cfg.Username}
		args = append(args, rt.hostArg...)
		if rt.cfg.CreateDatabase {
			args = append(args, "--create")
		}
		args = append(args, db)

		cmd := exec.Command("pg_dump", args...)
		cmd.Stdout = out
		cmd.Stderr = rt.log
		if err := cmd.Run(); err != nil {
			return fmt.Errorf("pg_dump failed for %s: %w", db, err)
		}
		_, _ = io.WriteString(out, "\n\n")
	}
	return nil
}

func (rt *Runtime) runToFile(name string, args []string, outputPath string) error {
	out, err := os.Create(outputPath)
	if err != nil {
		return err
	}
	defer out.Close()

	cmd := exec.Command(name, args...)
	cmd.Stdout = out
	cmd.Stderr = rt.log
	if err := cmd.Run(); err != nil {
		return fmt.Errorf("%s failed: %w", name, err)
	}
	return nil
}

func (rt *Runtime) compress(path string) (string, error) {
	switch strings.ToLower(rt.cfg.Compression) {
	case "gzip":
		finalPath := path + ".gz"
		if err := gzipFile(path, finalPath); err != nil {
			return "", err
		}
		if err := os.Remove(path); err != nil {
			return "", err
		}
		rt.printf("\nBackup Information for %s\n", path)
		rt.fileInfo(finalPath)
		return finalPath, nil
	case "bzip2":
		rt.printf("Compression information for %s.bz2\n", path)
		cmd := exec.Command("bzip2", "-f", "-v", path)
		cmd.Stdout = rt.log
		cmd.Stderr = rt.log
		if err := cmd.Run(); err != nil {
			return "", fmt.Errorf("bzip2 failed: %w", err)
		}
		return path + ".bz2", nil
	case "", "none", "no":
		rt.printf("Compression disabled for %s\n", path)
		return path, nil
	default:
		return "", fmt.Errorf("unknown compression option: %s", rt.cfg.Compression)
	}
}

func gzipFile(src, dst string) error {
	in, err := os.Open(src)
	if err != nil {
		return err
	}
	defer in.Close()

	out, err := os.Create(dst)
	if err != nil {
		return err
	}
	defer out.Close()

	gw := gzip.NewWriter(out)
	gw.Name = filepath.Base(src)
	gw.ModTime = time.Now()

	if _, err := io.Copy(gw, in); err != nil {
		_ = gw.Close()
		return err
	}
	return gw.Close()
}

func (rt *Runtime) fileInfo(path string) {
	st, err := os.Stat(path)
	if err != nil {
		rt.printf("Cannot stat %s: %v\n", path, err)
		return
	}
	rt.printf("Compressed file: %s\n", path)
	rt.printf("Size: %d bytes\n", st.Size())
}

func (rt *Runtime) diskUsage() {
	rt.printf("Total disk space used for backup storage..\n")
	rt.printf("Size - Location\n")

	cmd := exec.Command("du", "-hs", rt.cfg.BackupDir)
	cmd.Stdout = rt.log
	cmd.Stderr = rt.log
	_ = cmd.Run()
	rt.printBlank()
}

func (rt *Runtime) runShell(command string) error {
	cmd := exec.Command("sh", "-c", command)
	cmd.Stdout = rt.log
	cmd.Stderr = rt.log
	return cmd.Run()
}

func (rt *Runtime) finishOutput() error {
	if rt.log == nil {
		return nil
	}
	return rt.log.Close()
}

func (rt *Runtime) cleanupLog() {
	if rt.log != nil {
		_ = rt.log.Close()
	}
	if rt.logFile != "" {
		_ = os.Remove(rt.logFile)
	}
}

func (rt *Runtime) sendReport() {
	switch rt.cfg.MailContent {
	case "files":
		rt.sendFilesOrWarning()
	case "log":
		rt.sendLog("PostgreSQL Backup Log for " + rt.dbHostLabel + " - " + rt.date)
	default:
		data, err := os.ReadFile(rt.logFile)
		if err == nil {
			_, _ = os.Stdout.Write(data)
		}
	}
}

func (rt *Runtime) sendFilesOrWarning() {
	totalKB := int64(0)
	for _, f := range rt.backupFiles {
		if st, err := os.Stat(f); err == nil {
			totalKB += st.Size() / 1024
		}
	}

	if totalKB > int64(rt.cfg.MaxAttachmentKB) {
		rt.sendLog("WARNING! - PostgreSQL Backup exceeds set maximum attachment size on " + rt.dbHostLabel + " - " + rt.date)
		return
	}

	args := []string{"-s", "PostgreSQL Backup Log and SQL Files for " + rt.dbHostLabel + " - " + rt.date}
	for _, f := range rt.backupFiles {
		args = append(args, "-a", f)
	}
	args = append(args, rt.cfg.MailAddr)

	logData, _ := os.ReadFile(rt.logFile)
	cmd := exec.Command("mutt", args...)
	cmd.Stdin = bytes.NewReader(logData)
	cmd.Stdout = os.Stdout
	cmd.Stderr = os.Stderr
	_ = cmd.Run()
}

func (rt *Runtime) sendLog(subject string) {
	data, err := os.ReadFile(rt.logFile)
	if err != nil {
		fmt.Fprintln(os.Stderr, err)
		return
	}

	cmd := exec.Command("mail", "-s", subject, rt.cfg.MailAddr)
	cmd.Stdin = bytes.NewReader(data)
	cmd.Stdout = os.Stdout
	cmd.Stderr = os.Stderr
	_ = cmd.Run()
}

func (rt *Runtime) printHeader() {
	rt.printLine()
	rt.printf("AutoPostgreSQLBackup VER 1.0-go\n")
	rt.printf("http://autopgsqlbackup.frozenpc.net/\n\n")
	rt.printf("Backup of Database Server - %s\n", rt.dbHostLabel)
	rt.printLine()
}

func (rt *Runtime) printSection(title string) {
	rt.printLine()
	rt.printf("%s\n\n", title)
}

func (rt *Runtime) printLine() {
	rt.printf("======================================================================\n")
}

func (rt *Runtime) printDash() {
	rt.printf("----------------------------------------------------------------------\n")
}

func (rt *Runtime) printBlank() {
	rt.printf("\n")
}

func (rt *Runtime) printf(format string, args ...any) {
	_, _ = fmt.Fprintf(rt.log, format, args...)
}

func ensureDirs(paths ...string) error {
	for _, p := range paths {
		if err := os.MkdirAll(p, 0755); err != nil {
			return err
		}
	}
	return nil
}

func removeGlob(pattern string) error {
	matches, err := filepath.Glob(pattern)
	if err != nil {
		return err
	}
	for _, m := range matches {
		if err := os.Remove(m); err != nil && !os.IsNotExist(err) {
			return err
		}
	}
	return nil
}

func isoWeekday(t time.Time) int {
	d := int(t.Weekday())
	if d == 0 {
		return 7
	}
	return d
}

func rotatedWeek(week int) int {
	if week <= 5 {
		return 48 + week
	}
	return week - 5
}

func splitWords(s string) []string {
	parts := strings.Fields(s)
	out := make([]string, 0, len(parts))
	for _, p := range parts {
		if p != "" {
			out = append(out, p)
		}
	}
	return out
}

func decodeDBName(s string) string {
	return strings.ReplaceAll(s, "%", " ")
}

func atoiDefault(s string, def int) int {
	n, err := strconv.Atoi(s)
	if err != nil {
		return def
	}
	return n
}
