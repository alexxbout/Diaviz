//
//  SectionPhotoProfil.swift
//  diaviz
//
//  Created by Alexandre on 21/06/2026.
//

import SwiftUI
import PhotosUI
import UIKit

/// Section d'en-tête de la sheet Profil — grand avatar centré (photo ou
/// initiale) avec un `PhotosPicker` pour **ajouter / modifier** la photo
/// et un bouton **supprimer** quand une photo est définie.
///
/// La photo choisie est réduite (plus grand côté ~512 px, JPEG 0.8) avant
/// d'être persistée dans le profil (`UserDefaults`), pour garder un blob
/// léger. Auto-save immédiat via `ProfilService`, comme le reste du profil.
struct SectionPhotoProfil: View {

    @Environment(ProfilService.self) private var service

    /// Élément choisi dans le `PhotosPicker` — remis à `nil` une fois
    /// chargé pour qu'un nouveau choix du même média re-déclenche le load.
    @State private var selection: PhotosPickerItem?

    var body: some View {
        Section {
            VStack(spacing: 12) {
                AvatarProfil(
                    photoData: service.profil.photoData,
                    prenom: service.profil.prenom,
                    taille: 96
                )

                PhotosPicker(
                    selection: $selection,
                    matching: .images,
                    photoLibrary: .shared()
                ) {
                    Text(service.profil.photoData == nil ? "Ajouter une photo" : "Modifier la photo")
                        .font(.callout.weight(.semibold))
                }

                if service.profil.photoData != nil {
                    Button("Supprimer la photo", role: .destructive) {
                        service.definirPhotoProfil(nil)
                    }
                    .font(.callout)
                }
            }
            .frame(maxWidth: .infinity)
            .padding(.vertical, 8)
            .listRowBackground(Color.clear)
        }
        .onChange(of: selection) { _, nouveau in
            guard let nouveau else { return }
            Task { await chargerEtEnregistrer(nouveau) }
        }
    }

    /// Charge les données de l'élément choisi, les réduit, puis les
    /// enregistre dans le profil. Tolérant à l'échec (annulation, format
    /// illisible) : on ne touche pas au profil dans ce cas.
    private func chargerEtEnregistrer(_ item: PhotosPickerItem) async {
        guard let data = try? await item.loadTransferable(type: Data.self) else {
            selection = nil
            return
        }
        service.definirPhotoProfil(Self.reduireImage(data) ?? data)
        selection = nil
    }

    /// Réduit une image au plus grand côté `maxDimension` et la ré-encode
    /// en JPEG, pour garder le blob stocké léger (UserDefaults). Retourne
    /// `nil` si les données ne sont pas une image décodable.
    private static func reduireImage(_ data: Data, maxDimension: CGFloat = 512) -> Data? {
        guard let image = UIImage(data: data) else { return nil }
        let cote = max(image.size.width, image.size.height)
        let echelle = cote > maxDimension ? maxDimension / cote : 1
        let taille = CGSize(width: image.size.width * echelle, height: image.size.height * echelle)
        let format = UIGraphicsImageRendererFormat.default()
        format.scale = 1
        let renderer = UIGraphicsImageRenderer(size: taille, format: format)
        let reduite = renderer.image { _ in
            image.draw(in: CGRect(origin: .zero, size: taille))
        }
        return reduite.jpegData(compressionQuality: 0.8)
    }
}
