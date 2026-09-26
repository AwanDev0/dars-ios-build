import SwiftUI

struct SidebarTabs: View {
    let tabs: [DarsTabItem]
    @Binding var selected: String

    var body: some View {
        List(selection: Binding(get: { Optional(selected) }, set: { if let v = $0 { selected = v } })) {
            ForEach(tabs) { tab in
                Label {
                    Text(verbatim: tab.title)
                } icon: {
                    MaterialIcon(tab.id == selected ? tab.icon : tab.iconOutline, size: 22)
                }
                .tag(tab.id)
            }
        }
        .listStyle(.sidebar)
        .navigationTitle(Text(verbatim: "Dars"))
        .tint(Tokens.accent)
    }
}

enum RoleTabs {
    static func of(_ role: Role) -> [DarsTabItem] {
        switch role {
        case .student:
            return [
                DarsTabItem(id: "home", titleKey: "tabs_home", icon: "Filled.Home", iconOutline: "Outlined.Home"),
                DarsTabItem(id: "schedule", titleKey: "tabs_schedule", icon: "Filled.CalendarMonth", iconOutline: "Outlined.CalendarMonth"),
                DarsTabItem(id: "work", titleKey: "tabs_work", icon: "AutoMirrored.Filled.Article", iconOutline: "AutoMirrored.Outlined.Article"),
                DarsTabItem(id: "marks", titleKey: "tabs_grades", icon: "Filled.WorkspacePremium", iconOutline: "Outlined.WorkspacePremium"),
                DarsTabItem(id: "messages", titleKey: "tabs_chat", icon: "AutoMirrored.Filled.Chat", iconOutline: "AutoMirrored.Outlined.Chat"),
                DarsTabItem(id: "profile", titleKey: "tabs_profile", icon: "Filled.AccountCircle", iconOutline: "Outlined.AccountCircle"),
            ]
        case .parent:
            return [
                DarsTabItem(id: "home", titleKey: "tabs_children", icon: "Filled.School", iconOutline: "Outlined.School"),
                DarsTabItem(id: "messages", titleKey: "tabs_chat", icon: "AutoMirrored.Filled.Chat", iconOutline: "AutoMirrored.Outlined.Chat"),
                DarsTabItem(id: "profile", titleKey: "tabs_profile", icon: "Filled.AccountCircle", iconOutline: "Outlined.AccountCircle"),
            ]
        case .teacher:
            return [
                DarsTabItem(id: "home", titleKey: "tabs_home", icon: "Filled.Home", iconOutline: "Outlined.Home"),
                DarsTabItem(id: "classes", titleKey: "tabs_classes", icon: "Filled.Class", iconOutline: "Outlined.Class"),
                DarsTabItem(id: "post", titleKey: "tabs_post", icon: "Filled.AddCircle", iconOutline: "Outlined.AddCircle", isPost: true),
                DarsTabItem(id: "messages", titleKey: "tabs_chat", icon: "AutoMirrored.Filled.Chat", iconOutline: "AutoMirrored.Outlined.Chat"),
                DarsTabItem(id: "profile", titleKey: "tabs_profile", icon: "Filled.AccountCircle", iconOutline: "Outlined.AccountCircle"),
            ]
        case .admin:
            return [
                DarsTabItem(id: "home", titleKey: "tabs_overview", icon: "Filled.BarChart", iconOutline: "Outlined.BarChart"),
                DarsTabItem(id: "people", titleKey: "tabs_people", icon: "Filled.People", iconOutline: "Outlined.People"),
                DarsTabItem(id: "classes", titleKey: "tabs_classes", icon: "AutoMirrored.Filled.LibraryBooks", iconOutline: "AutoMirrored.Outlined.LibraryBooks"),
                DarsTabItem(id: "messages", titleKey: "tabs_chat", icon: "AutoMirrored.Filled.Chat", iconOutline: "AutoMirrored.Outlined.Chat"),
                DarsTabItem(id: "profile", titleKey: "tabs_profile", icon: "Filled.AccountCircle", iconOutline: "Outlined.AccountCircle"),
            ]
        }
    }
}
