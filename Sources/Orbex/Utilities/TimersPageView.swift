import SwiftUI
import OrbexCore

/// Página "Timers" de la isla abierta (≈ 270 × 230 pt): timers, atajos y cronómetro.
struct TimersPageView: View {
    @ObservedObject private var store = TimersStore.shared
    @Environment(\.orbexTheme) private var theme

    init() {}

    var body: some View {
        VStack(spacing: 6) {
            ScrollView(.vertical, showsIndicators: false) {
                VStack(spacing: 5) {
                    if store.timers.isEmpty && !store.stopwatch.hasStarted {
                        Text("Sin timers. ¿Arrancamos uno? ⏱")
                            .font(.system(size: 11, weight: .medium, design: .rounded))
                            .foregroundStyle(theme.secondaryText)
                            .frame(maxWidth: .infinity)
                            .padding(.vertical, 18)
                    }
                    ForEach(store.timers) { timer in
                        TimerRow(timer: timer, now: store.now)
                    }
                    StopwatchSection(stopwatch: store.stopwatch, now: store.now)
                }
            }
            HStack(spacing: 5) {
                quick("+1", minutes: 1)
                quick("+5", minutes: 5)
                quick("+25", minutes: 25)
                Button { store.startPomodoro() } label: {
                    Text("🍅 Pomodoro")
                        .font(.system(size: 10.5, weight: .semibold, design: .rounded))
                        .foregroundStyle(theme.text)
                        .frame(maxWidth: .infinity)
                        .frame(height: 24)
                        .orbexCard(cornerRadius: 12)
                }
                .buttonStyle(.plain)
                .help("25 min de foco y 5 de descanso")
            }
        }
        .background(Color.black)
    }

    private func quick(_ title: String, minutes: Int) -> some View {
        Button { store.startTimer(seconds: TimeInterval(minutes * 60)) } label: {
            Text(title)
                .font(.system(size: 10.5, weight: .semibold, design: .rounded))
                .foregroundStyle(theme.accent)
                .frame(width: 38, height: 24)
                .orbexCard(cornerRadius: 12)
        }
        .buttonStyle(.plain)
        .help("Timer de \(minutes) min")
    }
}

/// Fila de un timer: anillo, nombre, lo que falta y botones.
struct TimerRow: View {
    let timer: OrbexTimer
    let now: Date
    @Environment(\.orbexTheme) private var theme

    var body: some View {
        HStack(spacing: 8) {
            TimerRingView(progress: timer.progress(at: now), size: 24, lineWidth: 3.5)
            VStack(alignment: .leading, spacing: 1) {
                Text(timer.displayName)
                    .font(.system(size: 11, weight: .semibold, design: .rounded))
                    .foregroundStyle(theme.text)
                    .lineLimit(1)
                Text(timer.isFinished ? "¡Listo!" : TimerFormat.countdown(timer.remaining(at: now)))
                    .font(.system(size: 12, weight: .medium, design: .rounded))
                    .monospacedDigit()
                    .foregroundStyle(timer.isFinished ? theme.accent : theme.secondaryText)
            }
            Spacer(minLength: 0)
            if !timer.isFinished {
                iconButton(timer.isPaused ? "play.fill" : "pause.fill",
                           help: timer.isPaused ? "Reanudar" : "Pausar") {
                    TimersStore.shared.togglePause(timer.id)
                }
                iconButton("plus", help: "Sumar 1 minuto") {
                    TimersStore.shared.addTime(timer.id, seconds: 60)
                }
            }
            iconButton("xmark", help: timer.isFinished ? "Listo" : "Parar") {
                TimersStore.shared.stop(timer.id)
            }
        }
        .padding(.horizontal, 8)
        .padding(.vertical, 5)
        .orbexCard(cornerRadius: 12)
    }

    private func iconButton(_ symbol: String, help: String, action: @escaping () -> Void) -> some View {
        Button(action: action) {
            Image(systemName: symbol)
                .font(.system(size: 9.5, weight: .bold))
                .foregroundStyle(theme.secondaryText)
                .frame(width: 20, height: 20)
                .background(Circle().fill(Color.white.opacity(0.08)))
        }
        .buttonStyle(.plain)
        .help(help)
    }
}

/// Cronómetro con vueltas.
struct StopwatchSection: View {
    let stopwatch: Stopwatch
    let now: Date
    @Environment(\.orbexTheme) private var theme

    var body: some View {
        VStack(alignment: .leading, spacing: 4) {
            HStack(spacing: 6) {
                Image(systemName: "stopwatch")
                    .font(.system(size: 11, weight: .semibold))
                    .foregroundStyle(theme.accent)
                Text(TimerFormat.stopwatch(stopwatch.elapsed(at: now)))
                    .font(.system(size: 13, weight: .semibold, design: .rounded))
                    .monospacedDigit()
                    .foregroundStyle(theme.text)
                Spacer(minLength: 0)
                small(stopwatch.isRunning ? "Pausa" : (stopwatch.hasStarted ? "Seguir" : "Iniciar")) {
                    TimersStore.shared.toggleStopwatch()
                }
                if stopwatch.isRunning {
                    small("Vuelta") { TimersStore.shared.lap() }
                } else if stopwatch.hasStarted {
                    small("Reiniciar") { TimersStore.shared.resetStopwatch() }
                }
            }
            ForEach(stopwatch.laps.prefix(3)) { lap in
                HStack {
                    Text("Vuelta \(lap.number)")
                    Spacer()
                    Text(TimerFormat.stopwatch(lap.duration)).monospacedDigit()
                }
                .font(.system(size: 10, design: .rounded))
                .foregroundStyle(theme.secondaryText)
            }
        }
        .padding(.horizontal, 8)
        .padding(.vertical, 6)
        .orbexCard(cornerRadius: 12)
    }

    private func small(_ title: String, action: @escaping () -> Void) -> some View {
        Button(action: action) {
            Text(title)
                .font(.system(size: 10, weight: .semibold, design: .rounded))
                .foregroundStyle(theme.accent)
                .padding(.horizontal, 7)
                .frame(height: 20)
                .background(Capsule().fill(Color.white.opacity(0.08)))
        }
        .buttonStyle(.plain)
    }
}
