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
            // Avatar seul dans sa row — vue de présentation pure, sans
            // aucun geste attaché. Avant, il partageait une row avec les
            // deux boutons ci-dessous (une seule `VStack` = une seule row
            // de `Form`) ; empilés sans séparation, un tap sur l'avatar
            // pouvait être résolu par iOS vers le bouton « Supprimer » du
            // dessous au lieu de rester inerte. Chaque contrôle a
            // maintenant sa propre row et son propre `contentShape`.
            HStack {
                Spacer()
                AvatarProfil(
                    photoData: service.profil.photoData,
                    prenom: service.profil.prenom,
                    taille: 96
                )
                .contentShape(Circle())
                Spacer()
            }
            .listRowBackground(Color.clear)
            .listRowSeparator(.hidden)

            // Le label de `PhotosPicker` est un `@Sendable` closure — on
            // calcule le libellé avant plutôt que de lire `service`
            // (MainActor-isolé) depuis l'intérieur de la closure.
            // `HStack` + `Spacer` de chaque côté : centre le texte comme
            // avant (une row de `Form` aligne son contenu à gauche par
            // défaut, `.frame(maxWidth:)` seul ne suffit pas à centrer).
            HStack {
                // Copié ici : le libellé du sélecteur est construit hors du
                // thread principal, il ne peut pas lire le profil.
                let libelle = libellePhotoPicker
                Spacer()
                PhotosPicker(
                    selection: $selection,
                    matching: .images,
                    photoLibrary: .shared()
                ) {
                    Text(libelle)
                        .font(.callout.weight(.semibold))
                }
                Spacer()
            }
            .contentShape(Rectangle())
            .listRowBackground(Color.clear)
            .listRowSeparator(.hidden)

            if service.profil.photoData != nil {
                HStack {
                    Spacer()
                    Button("Supprimer la photo", role: .destructive) {
                        service.definirPhotoProfil(nil)
                    }
                    .font(.callout)
                    Spacer()
                }
                .listRowBackground(Color.clear)
                .listRowSeparator(.hidden)
                .contentShape(Rectangle())
            }
        }
        .onChange(of: selection) { _, nouveau in
            guard let nouveau else { return }
            Task { await chargerEtEnregistrer(nouveau) }
        }
    }

    private var libellePhotoPicker: String {
        service.profil.photoData == nil ? "Ajouter une photo" : "Modifier la photo"
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
