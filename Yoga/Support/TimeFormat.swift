/// `mm:ss`, minutes are not wrapped at 60 — same as the web app.
func formatTime(_ seconds: Int) -> String {
    let minutes = seconds / 60
    let rest = seconds % 60

    return String(format: "%02d:%02d", minutes, rest)
}
