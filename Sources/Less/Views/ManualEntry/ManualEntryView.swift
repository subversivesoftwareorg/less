import SwiftUI

struct ManualEntryView: View {
    @Environment(\.appDatabase) private var database
    @Environment(\.dismiss) private var dismiss

    @State private var consumptionType: ConsumptionType = .electricity
    @State private var quantity: String = ""
    @State private var unit: String = "kWh"
    @State private var date: Date = .now
    @State private var description: String = ""
    @State private var amount: String = ""
    @State private var errorMessage: String?
    @State private var saved = false

    var body: some View {
        Form {
            Section("Consumption Type") {
                Picker("Type", selection: $consumptionType) {
                    ForEach(ConsumptionType.allCases.filter { $0 != .money }) { type in
                        Label(type.displayName, systemImage: type.icon)
                            .tag(type)
                    }
                }
                .onChange(of: consumptionType) { _, newValue in
                    unit = newValue.defaultUnit
                }
            }

            Section("Measurement") {
                HStack {
                    TextField("Quantity", text: $quantity)
                        .textFieldStyle(.roundedBorder)

                    Picker("Unit", selection: $unit) {
                        ForEach(consumptionType.allUnits, id: \.self) { u in
                            Text(u).tag(u)
                        }
                    }
                    .frame(width: 120)
                }

                DatePicker("Date", selection: $date, displayedComponents: .date)
            }

            Section("Details (Optional)") {
                TextField("Description", text: $description,
                          prompt: Text("e.g., Electric meter reading"))
                    .textFieldStyle(.roundedBorder)

                TextField("Cost ($)", text: $amount,
                          prompt: Text("Dollar amount if known"))
                    .textFieldStyle(.roundedBorder)
            }

            Section {
                HStack {
                    if saved {
                        Label("Entry saved!", systemImage: "checkmark.circle.fill")
                            .foregroundStyle(.green)
                    }

                    if let error = errorMessage {
                        Label(error, systemImage: "exclamationmark.triangle")
                            .foregroundStyle(.red)
                            .font(.caption)
                    }

                    Spacer()

                    Button("Save Entry") {
                        saveEntry()
                    }
                    .buttonStyle(.borderedProminent)
                    .disabled(quantity.isEmpty)
                }
            }
        }
        .formStyle(.grouped)
        .frame(minWidth: 400, minHeight: 350)
    }

    private func saveEntry() {
        guard let qty = Double(quantity), qty > 0 else {
            errorMessage = "Enter a valid quantity."
            return
        }

        let dollarAmount = Double(amount) ?? 0
        let desc = description.isEmpty ? "\(consumptionType.displayName) entry" : description

        do {
            try database.saveManualEntry(
                description: desc,
                amount: dollarAmount,
                quantity: qty,
                unit: unit,
                date: date
            )
            saved = true
            errorMessage = nil

            // Reset form for next entry
            DispatchQueue.main.asyncAfter(deadline: .now() + 1.5) {
                saved = false
                quantity = ""
                amount = ""
                description = ""
            }

            dlog("Manual entry saved: \(qty) \(unit)", category: "ManualEntry")
        } catch {
            errorMessage = error.localizedDescription
        }
    }
}
