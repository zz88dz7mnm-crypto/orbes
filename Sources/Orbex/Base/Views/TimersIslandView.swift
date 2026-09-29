import SwiftUI
import OrbexCore

/// Vista "Timers" de la isla: los que están corriendo (con anillo), iniciar rápido, pomodoro y cronómetro.
struct TimersIslandView: View {
    @ObservedObject var state: AppState
    @ObservedObject private var store = TimersStore.shared

    var body: some View {
        CardBackground(wash: nil) {
            HStack(alignment: .top, spacing: 12) {
                VStack(spacing: 6) {
                    runningList
                    IslandStopwatchRow(stopwatch: store.stopwatch, now: store.now)
                }
                .frame(maxWidth: .infinity, maxHeight: .infinity, alignment: .top)

                quickColumn
                    .frame(width: 164)
            }
            .padding(.leading, IslandPalette.botGutter)
            .padding(.trailing, 12)
            .padding(.vertical, 10)
        }
    }

    @ViewBuilder
    private var runningList: some View {
        if store.timers.isEmpty {
            VStack(spacing: 3) {
                Text("No hay timers corriendo")
                    .font(.system(size: 12, weight: .semibold, design: .rounded))
                    .foregroundColor(IslandPalette.text)
                Text("Arrancá uno con los botones de la derecha ⏱")
                    .font(.system(size: 10.5, design: .rounded))
                    .foregroundColor(IslandPalette.secondary)
            }
            .frame(maxWidth: .infinity, maxHeight: .infinity)
        } else {
            ScrollView(.vertical, showsIndicators: false) {
                VStack(spacing: 5) {
                    ForEach(store.timers) { timer in
                        IslandTimerRow(timer: timer, now: store.now)
                    }
                }
            }
            .frame(maxHeight: .infinity)
        }
    }

    private var quickColumn: some View {
        VStack(alignment: .leading, spacing: 6) {
            Text("Iniciar rápido")
                .font(.system(size: 10, weight: .semibold, design: .rounded))
                .foregroundColor(IslandPalette.tertiary)
            let cols = [GridItem(.flexible(), spacing: 6), GridItem(.flexible(), spacing: 6)]
            LazyVGrid(columns: cols, spacing: 6) {
                ForEach([1, 5, 10, 25], id: \.self) { m in
                    IslandChipButton(title: "\(m) min", expand: true, help: "Timer de \(m) minuto\(m == 1 ? "" : "s")") {
                        store.startTimer(seconds: TimeInterval(m * 60))
                    }
                }
            }
            IslandChipButton(title: "Pomodoro", symbol: "brain.head.profile", tint: Color(hex: "#F4505E"),
                             expand: true, help: "25 min de foco y 5 de descanso") {
                store.startPomodoro()
            }
            Spacer(minLength: 0)
        }
    }
}

/// Fila de un timer en la isla: anillo, nombre, lo que falta y botones.
struct IslandTimerRow: View {
    let timer: OrbexTimer
    let now: Date

    var body: some View {
        HStack(spacing: 8) {
            TimerRingView(progress: timer.progress(at: now), size: 22, lineWidth: 3)
            VStack(alignment: .leading, spacing: 0) {
                Text(timer.displayName)
                    .font(.system(size: 11.5, weight: .semibold, design: .rounded))
                    .foregroundColor(IslandPalette.text)
                    .lineLimit(1)
                Text(subtitle)
                    .font(.system(size: 11, weight: .medium, design: .rounded))
                    .monospacedDigit()
                    .foregroundColor(timer.isFinished ? Color(hex: "#34D399") : IslandPalette.secondary)
            }
            Spacer(minLength: 0)
            if !timer.isFinished {
                IslandIconButton(symbol: timer.isPaused ? "play.fill" : "pause.fill",
                                 help: timer.isPaused ? "Seguir" : "Pausar") {
                    TimersStore.shared.togglePause(timer.id)
                }
                IslandIconButton(symbol: "plus", help: "Sumar 1 minuto") {
                    TimersStore.shared.addTime(timer.id, seconds: 60)
                }
            }
            IslandIconButton(symbol: "xmark", help: timer.isFinished ? "Listo" : "Parar") {
                TimersStore.shared.stop(timer.id)
            }
        }
        .padding(.horizontal, 8)
        .padding(.vertical, 4)
        .background(RoundedRectangle(cornerRadius: 10).fill(Color.white.opacity(0.05)))
    }

    private var subtitle: String {
        if timer.isFinished { return "¡Listo!" }
        let left = TimerFormat.countdown(timer.remaining(at: now))
        return timer.isPaused ? "\(left) · en pausa" : left
    }
}

/// Cronómetro en una fila.
struct IslandStopwatchRow: View {
    let stopwatch: Stopwatch
    let now: Date

    var body: some View {
        HStack(spacing: 8) {
            Image(systemName: "stopwatch")
                .font(.system(size: 12, weight: .semibold))
                .foregroundColor(IslandPalette.secondary)
            Text(TimerFormat.stopwatch(stopwatch.elapsed(at: now)))
                .font(.system(size: 13, weight: .semibold, design: .rounded))
                .monospacedDigit()
                .foregroundColor(stopwatch.hasStarted ? IslandPalette.text : IslandPalette.tertiary)
            if let lap = stopwatch.laps.first {
                Text("Vuelta \(lap.number): \(TimerFormat.stopwatch(lap.duration))")
                    .font(.system(size: 10, design: .rounded))
                    .monospacedDigit()
                    .foregroundColor(IslandPalette.tertiary)
                    .lineLimit(1)
            }
            Spacer(minLength: 0)
            IslandChipButton(title: stopwatch.isRunning ? "Pausa" : (stopwatch.hasStarted ? "Seguir" : "Cronómetro"),
                             height: 20) {
                TimersStore.shared.toggleStopwatch()
            }
            if stopwatch.isRunning {
                IslandChipButton(title: "Vuelta", height: 20) { TimersStore.shared.lap() }
            } else if stopwatch.hasStarted {
                IslandChipButton(title: "Reiniciar", height: 20) { TimersStore.shared.resetStopwatch() }
            }
        }
        .padding(.horizontal, 8)
        .padding(.vertical, 4)
        .background(RoundedRectangle(cornerRadius: 10).fill(Color.white.opacity(0.05)))
    }
}

/// Fila para el resumen (overview): el próximo timer en terminar (o el cronómetro) y "+N más".
/// Si no hay nada corriendo no ocupa lugar. Tocarla abre la vista de timers.
struct TimerSummaryRow: View {
    @ObservedObject private var store = TimersStore.shared
    @ObservedObject private var state = AppState.shared

    init() {}

    var body: some View {
        let timers = store.timers
        let main = timers.first(where: \.isFinished) ?? store.engine.nextToFinish ?? timers.first
        if main != nil || store.stopwatch.isRunning {
            Button {
                withAnimation(.spring(response: 0.3, dampingFraction: 0.8)) { state.view = .timers }
            } label: {
                HStack(spacing: 6) {
                    if let t = main {
                        TimerRingView(progress: t.progress(at: store.now), size: 12, lineWidth: 2)
                        Text(t.displayName)
                            .font(.system(size: 11, weight: .semibold, design: .rounded))
                            .foregroundColor(IslandPalette.text)
                            .lineLimit(1)
                        Text(t.isFinished ? "¡Listo!" : TimerFormat.countdown(t.remaining(at: store.now)))
                            .font(.system(size: 11, weight: .medium, design: .rounded))
                            .monospacedDigit()
                            .foregroundColor(t.isFinished ? Color(hex: "#34D399") : IslandPalette.secondary)
                        if timers.count > 1 {
                            Text("+\(timers.count - 1) más")
                                .font(.system(size: 10, design: .rounded))
                                .foregroundColor(IslandPalette.tertiary)
                        }
                    } else {
                        Image(systemName: "stopwatch")
                            .font(.system(size: 10, weight: .semibold))
                            .foregroundColor(IslandPalette.secondary)
                        Text(TimerFormat.stopwatch(store.stopwatch.elapsed(at: store.now)))
                            .font(.system(size: 11, weight: .medium, design: .rounded))
                            .monospacedDigit()
                            .foregroundColor(IslandPalette.secondary)
                    }
                }
                .padding(.horizontal, 8)
                .frame(height: 20)
                .background(Capsule().fill(Color.white.opacity(0.06)))
                .contentShape(Capsule())
            }
            .buttonStyle(.plain)
            .help("Ver timers")
        }
    }
}
