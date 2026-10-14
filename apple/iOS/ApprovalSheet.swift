import SwiftUI

/// Claude Code wants to run a gated tool: what and Approve / Deny. Denied by the hub after 60 s.
struct ApprovalSheet: View {
    let approval: Approval
    let decide: (Bool) -> Void

    var body: some View {
        VStack(alignment: .leading, spacing: 18) {
            Label("Approval needed", systemImage: "exclamationmark.shield.fill")
                .font(.system(.headline, design: .rounded))
                .foregroundStyle(.orange)

            VStack(alignment: .leading, spacing: 10) {
                Text("Claude Code wants to use **\(approval.tool)**")
                    .font(.system(.title3, design: .rounded))
                if !approval.summary.isEmpty {
                    Text(approval.summary)
                        .font(.system(.body, design: .monospaced))
                        .lineLimit(4)
                        .textSelection(.enabled)
                        .frame(maxWidth: .infinity, alignment: .leading)
                        .padding(14)
                        .background(RoundedRectangle(cornerRadius: 14, style: .continuous).fill(.white.opacity(0.07)))
                }
            }

            HStack(spacing: 4) {
                Text("Denied automatically in")
                Text(timerInterval: approval.since...approval.since.addingTimeInterval(Approval.timeout), countsDown: true)
                    .monospacedDigit()
            }
            .font(.footnote)
            .foregroundStyle(.secondary)

            Spacer(minLength: 0)

            HStack(spacing: 12) {
                Button(role: .destructive) { decide(false) } label: {
                    Text("Deny").frame(maxWidth: .infinity)
                }
                .buttonStyle(.bordered)
                .tint(.red)
                Button { decide(true) } label: {
                    Text("Approve").frame(maxWidth: .infinity)
                }
                .buttonStyle(.borderedProminent)
                .tint(.green)
            }
            .controlSize(.large)
            .font(.system(.body, design: .rounded, weight: .semibold))
        }
        .padding(24)
        .presentationDetents([.height(300)])
        .presentationDragIndicator(.hidden)
        .interactiveDismissDisabled()
    }
}
