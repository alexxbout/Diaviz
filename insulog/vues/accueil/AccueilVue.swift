//
//  ChatView.swift
//  insulog
//
//  Created by Alexandre on 19/04/2026.
//

import SwiftUI

struct AccueilVue: View {
    var body: some View {
            NavigationStack {
                VStack(spacing: 0) {
                    
                    // Header custom
                    HStack {
                        Text("Accueil")
                            .font(.largeTitle)
                            .fontWeight(.bold)
                        
                        Spacer()
                        
                        Button {
                            print("Profil cliqué")
                        } label: {
                            Circle()
                                .fill(.blue)
                                .frame(width: 36, height: 36)
                                .overlay {
                                    Text("AB")
                                        .font(.caption)
                                        .foregroundStyle(.white)
                                }
                        }
                        .buttonStyle(.plain)
                    }
                    .padding(.horizontal)
                    .padding(.top, 8)
                    
                    // Contenu
                    Spacer()
                }
                .navigationBarHidden(false)
            }
        }
}

#Preview {
    AccueilVue()
}
