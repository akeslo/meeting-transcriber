import SwiftUI

// MARK: - NavItem

enum NavItem: String, CaseIterable, Identifiable {
    case dashboard = "Dashboard"
    case library   = "Library"
    case stats     = "Stats"
    case settings  = "Settings"

    var id: String { rawValue }

    var systemImage: String {
        switch self {
        case .dashboard: return "square.grid.2x2"
        case .library:   return "folder"
        case .stats:     return "chart.bar"
        case .settings:  return "gearshape"
        }
    }
}

// MARK: - SidebarView

struct SidebarView: View {
    @Binding var selectedNav: NavItem

    var engineLabel: String
    var storageLabel: String

    private let spaceIndigo = Color(red: 0.082, green: 0.114, blue: 0.208)
    private let peachGlow   = Color(red: 0.969, green: 0.773, blue: 0.624)
    private let aliceBlue   = Color(red: 0.882, green: 0.898, blue: 0.933)
    private let slateGrey   = Color(red: 0.780, green: 0.800, blue: 0.859)

    var body: some View {
        VStack(alignment: .leading, spacing: 0) {
            Text("Meeting Transcriber")
                .font(.system(size: 13, weight: .semibold))
                .foregroundStyle(.white)
                .padding(.horizontal, 20)
                .padding(.top, 24)
                .padding(.bottom, 16)

            ForEach(NavItem.allCases) { item in
                navRow(item)
            }

            Spacer()

            VStack(alignment: .leading, spacing: 4) {
                Text(engineLabel)
                    .font(.system(size: 11))
                    .foregroundStyle(slateGrey)
                Text(storageLabel)
                    .font(.system(size: 11))
                    .foregroundStyle(slateGrey)
            }
            .padding(.horizontal, 20)
            .padding(.bottom, 20)
        }
        .frame(width: 240)
        .background(spaceIndigo)
    }

    @ViewBuilder
    private func navRow(_ item: NavItem) -> some View {
        let isActive = selectedNav == item

        Button {
            selectedNav = item
        } label: {
            HStack(spacing: 10) {
                Rectangle()
                    .fill(isActive ? peachGlow : Color.clear)
                    .frame(width: 3, height: 20)
                    .cornerRadius(1.5)

                Image(systemName: item.systemImage)
                    .font(.system(size: 14))
                    .foregroundStyle(isActive ? .white : slateGrey)
                    .frame(width: 20)

                Text(item.rawValue)
                    .font(.system(size: 13, weight: isActive ? .semibold : .regular))
                    .foregroundStyle(isActive ? .white : slateGrey)

                Spacer()
            }
            .padding(.leading, 0)
            .padding(.trailing, 16)
            .padding(.vertical, 10)
            .background(
                isActive
                    ? aliceBlue.opacity(0.15)
                    : Color.clear
            )
        }
        .buttonStyle(.plain)
    }
}
