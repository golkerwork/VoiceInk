import SwiftUI

struct AppSidebar: View {
    @Binding var selectedView: ViewType

    var body: some View {
        ZStack(alignment: .trailing) {
            sidebarBackground
            sidebarDivider
            sidebarContent
        }
        .frame(width: 220)
        .frame(maxHeight: .infinity)
        .onAppear {
            ViewType.assertSidebarItemsCoverAllCases()
        }
    }

    private var sidebarContent: some View {
        VStack(spacing: 0) {
            sidebarSection(ViewType.primaryItems)
                .padding(.top, 10)

            Spacer(minLength: 16)

            sidebarSection(ViewType.secondaryItems)
                .padding(.bottom, 14)
        }
        .frame(maxWidth: .infinity, maxHeight: .infinity)
    }

    private var sidebarBackground: some View {
        AppTheme.Palette.sidebar
            .ignoresSafeArea(.container, edges: .top)
    }

    private var sidebarDivider: some View {
        Rectangle()
            .fill(AppTheme.Palette.border)
            .frame(width: 1)
            .ignoresSafeArea(.container, edges: .top)
    }

    private func sidebarSection(_ items: [ViewType]) -> some View {
        VStack(spacing: 3) {
            ForEach(items) { viewType in
                SidebarItemButton(
                    viewType: viewType,
                    isSelected: selectedView == viewType
                ) {
                    selectedView = viewType
                }
            }
        }
        .padding(.horizontal, 10)
    }
}

private extension ViewType {
    var title: LocalizedStringKey {
        switch self {
        case .transcribeAudio:
            return "Transcribe"
        default:
            return LocalizedStringKey(rawValue)
        }
    }

    static let primaryItems: [ViewType] = [
        .dashboard,
        .meetings,
        .modes,
        .transcribeAudio,
        .history,
        .dictionary,
        .models,
        .audio,
    ]

    // Local builds are already unlocked, so the license page would only be an upsell.
    #if LOCAL_BUILD
        static let secondaryItems: [ViewType] = [.settings]
        private static let hiddenItems: Set<ViewType> = [.license]
    #else
        static let secondaryItems: [ViewType] = [
            .settings,
            .license,
        ]
        private static let hiddenItems: Set<ViewType> = []
    #endif

    static func assertSidebarItemsCoverAllCases() {
        #if DEBUG
            let sidebarItems = primaryItems + secondaryItems
            assert(
                Set(sidebarItems).union(hiddenItems) == Set(allCases)
                    && sidebarItems.count + hiddenItems.count == allCases.count
            )
        #endif
    }

    var icon: String {
        switch self {
        case .dashboard: return "gauge.medium"
        case .meetings: return "person.2.wave.2.fill"
        case .transcribeAudio: return "waveform.path"
        case .history: return "doc.text.fill"
        case .models: return "cpu"
        case .modes: return "sparkles.square.fill.on.square"
        case .audio: return "mic.fill"
        case .dictionary: return "text.book.closed.fill"
        case .settings: return "gearshape.fill"
        case .license: return "checkmark.seal.fill"
        }
    }

    // Dark, minimal look: icons sit on a quiet neutral tile, and only the selected page lights up in violet.
    func sidebarIconStyle(isSelected: Bool) -> SidebarIconStyle {
        isSelected
            ? .init(background: AppTheme.Sidebar.selectedTile, foreground: .white)
            : .init(background: AppTheme.Sidebar.tile, foreground: AppTheme.Sidebar.tileForeground)
    }
}

private struct SidebarIconStyle {
    let background: Color
    var foreground: Color = .white
}

private struct SidebarItemButton: View {
    let viewType: ViewType
    let isSelected: Bool
    let action: () -> Void

    var body: some View {
        Button(action: action) {
            HStack(spacing: 9) {
                SidebarIconTile(
                    systemName: viewType.icon,
                    style: viewType.sidebarIconStyle(isSelected: isSelected)
                )

                Text(viewType.title)
                    .font(.system(size: 13.5, weight: isSelected ? .semibold : .medium))
                    .lineLimit(1)

                Spacer(minLength: 0)
            }
            .foregroundStyle(isSelected ? Color.primary : AppTheme.Palette.textSecondary)
            .padding(.leading, 8)
            .padding(.trailing, 10)
            .frame(height: 38)
            .frame(maxWidth: .infinity, alignment: .leading)
            .background(rowBackground)
            .contentShape(RoundedRectangle(cornerRadius: 10, style: .continuous))
        }
        .buttonStyle(.plain)
        .help(viewType.title)
        .accessibilityLabel(viewType.title)
        .accessibilityAddTraits(isSelected ? .isSelected : [])
        .animation(.easeInOut(duration: 0.12), value: isSelected)
    }

    private var rowBackground: some View {
        RoundedRectangle(cornerRadius: 10, style: .continuous)
            .fill(rowBackgroundColor)
            .overlay {
                RoundedRectangle(cornerRadius: 10, style: .continuous)
                    .strokeBorder(rowBorderColor, lineWidth: 1)
            }
    }

    private var rowBackgroundColor: Color {
        isSelected ? AppTheme.Selection.fill : .clear
    }

    private var rowBorderColor: Color {
        isSelected ? AppTheme.Selection.border.opacity(0.6) : .clear
    }
}

private struct SidebarIconTile: View {
    let systemName: String
    let style: SidebarIconStyle

    var body: some View {
        ZStack {
            RoundedRectangle(cornerRadius: 7, style: .continuous)
                .fill(style.background)

            Image(systemName: systemName)
                .font(.system(size: 13, weight: .semibold))
                .symbolRenderingMode(.monochrome)
                .foregroundStyle(style.foreground)
        }
        .frame(width: 24, height: 24)
    }
}
