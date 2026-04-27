//
//  AppTabView.swift
//  insulog
//
//  Created by Alexandre on 19/04/2026.
//

import SwiftUI

struct AppTabVues: View {
    @State private var showingSearch = false
    
    var body: some View {
        TabView {
            Tab("Accueil", systemImage: "house") {
                AccueilVue()
            }
            
            Tab("Journal", systemImage: "long.text.page.and.pencil") {
                JournalVue(nombreRepas: 0, sections: [])
            }
            
            Tab("Analyses", systemImage: "chart.dots.scatter") {
                AnalysesVue()
            }
            
            Tab("Recherche", systemImage: "magnifyingglass", role: TabRole.search) {
                RecercheVue()
            }
        }
    }
}

#Preview {
    AppTabVues()
}
