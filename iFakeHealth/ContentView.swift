import SwiftUI

struct ContentView: View {
    @State private var stepsText = ""
    @State private var startDate = Date().addingTimeInterval(-30 * 60)
    @State private var endDate = Date()
    @State private var statusMessage: String?
    @State private var isError = false
    @State private var isWriting = false
    @State private var history: [WalkEntry] = []
    @State private var showAbout = false

    @State private var showSuccess = false
    @State private var animatedSteps = 0

    private var isRangeValid: Bool { startDate < endDate }

    var body: some View {
        NavigationStack {
            List {
                Section {
                    TextField("Step count", text: $stepsText)
                        .keyboardType(.numberPad)

                    DatePicker("From", selection: $startDate, displayedComponents: [.date, .hourAndMinute])
                    DatePicker("To", selection: $endDate, displayedComponents: [.date, .hourAndMinute])

                    Button {
                        write()
                    } label: {
                        HStack {
                            Spacer()
                            if isWriting {
                                ProgressView()
                            } else {
                                Text("Write to Health")
                                    .fontWeight(.semibold)
                            }
                            Spacer()
                        }
                    }
                    .disabled(isWriting || Int(stepsText) == nil || !isRangeValid)
                } footer: {
                    if !isRangeValid {
                        Text("End time must be after start time.")
                            .foregroundStyle(.red)
                    } else if let statusMessage {
                        Text(statusMessage)
                            .foregroundStyle(isError ? .red : .green)
                    }
                }

                Section("Sent to Health") {
                    if history.isEmpty {
                        Text("No entries yet")
                            .foregroundStyle(.secondary)
                    }
                    ForEach(history) { entry in
                        HistoryRow(entry: entry)
                            .swipeActions {
                                Button(role: .destructive) {
                                    delete(entry)
                                } label: {
                                    Label("Delete", systemImage: "trash")
                                }
                            }
                    }
                }
            }
            .navigationTitle("iFakeHealth")
            .toolbar {
                ToolbarItem(placement: .topBarTrailing) {
                    Button {
                        showAbout = true
                    } label: {
                        Image(systemName: "info.circle")
                    }
                }
            }
            .sheet(isPresented: $showAbout) {
                AboutView()
            }
            .overlay(alignment: .top) {
                if showSuccess {
                    SuccessBadge(steps: animatedSteps)
                        .padding(.top, 8)
                        .transition(.move(edge: .top).combined(with: .opacity))
                }
            }
        }
        .tint(.green)
        .task {
            do {
                try await HealthKitManager.shared.requestAuthorization()
            } catch {
                statusMessage = error.localizedDescription
                isError = true
            }
            await loadHistory()
        }
    }

    private func write() {
        guard let steps = Int(stepsText), steps > 0, isRangeValid else { return }
        isWriting = true
        statusMessage = nil

        Task {
            do {
                try await HealthKitManager.shared.requestAuthorization()
                try await HealthKitManager.shared.writeWalk(steps: steps, start: startDate, end: endDate)
                statusMessage = "Wrote \(steps) steps to Health."
                isError = false
                await loadHistory()
                await animateSuccess(steps: steps)
            } catch {
                statusMessage = error.localizedDescription
                isError = true
            }
            isWriting = false
        }
    }

    @MainActor
    private func animateSuccess(steps: Int) async {
        animatedSteps = 0
        withAnimation(.spring(response: 0.4, dampingFraction: 0.65)) {
            showSuccess = true
        }
        withAnimation(.easeOut(duration: 0.8)) {
            animatedSteps = steps
        }
        try? await Task.sleep(for: .seconds(1.8))
        withAnimation(.easeIn(duration: 0.3)) {
            showSuccess = false
        }
    }

    private func delete(_ entry: WalkEntry) {
        Task {
            do {
                try await HealthKitManager.shared.delete(entry)
                await loadHistory()
            } catch {
                statusMessage = error.localizedDescription
                isError = true
            }
        }
    }

    private func loadHistory() async {
        do {
            history = try await HealthKitManager.shared.fetchHistory()
        } catch {
            statusMessage = error.localizedDescription
            isError = true
        }
    }
}

private struct SuccessBadge: View {
    let steps: Int

    var body: some View {
        HStack(spacing: 8) {
            Image(systemName: "checkmark.circle.fill")
                .foregroundStyle(.white)
            Text("+\(steps) steps")
                .contentTransition(.numericText())
                .fontWeight(.semibold)
                .foregroundStyle(.white)
        }
        .padding(.horizontal, 16)
        .padding(.vertical, 10)
        .background(.green, in: Capsule())
        .shadow(color: .black.opacity(0.2), radius: 8, y: 4)
    }
}

private struct HistoryRow: View {
    let entry: WalkEntry

    var body: some View {
        HStack(spacing: 12) {
            Image(systemName: "figure.walk")
                .font(.title3)
                .foregroundStyle(.green)
                .frame(width: 28)

            VStack(alignment: .leading, spacing: 2) {
                Text("\(entry.steps) steps")
                    .fontWeight(.medium)
                Text("\(entry.distanceKm, specifier: "%.2f") km · \(Int(entry.kcal)) kcal")
                    .font(.caption)
                    .foregroundStyle(.secondary)
            }

            Spacer()

            Text(entry.writtenAt, format: .dateTime.day().month().hour().minute())
                .font(.caption2)
                .foregroundStyle(.secondary)
        }
    }
}

#Preview {
    ContentView()
}
