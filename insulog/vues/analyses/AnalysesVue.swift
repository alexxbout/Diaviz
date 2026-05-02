//
//  AnalysesView.swift
//  insulog
//
//  Created by Alexandre on 19/04/2026.
//

import SwiftUI

struct AnalysesVue: View {
    var body: some View {
        NavigationStack {
            VStack(spacing: 0) {
                EnTetePage(titre: "Analyses")

                VStack(spacing: 0) { }
                    .frame(maxWidth: .infinity, maxHeight: .infinity)
            }
            .background(Color(.systemGroupedBackground))
        }
    }
}

#Preview {
    AnalysesVue()
        .environment(ProfilService.mockComplet())
}
