//
//  OpenFoodFactsAPIClient.swift
//  diaviz
//
//  Created by Alexandre on 15/07/2026.
//

import Foundation
import OSLog

/// Erreurs du client Open Food Facts.
enum OFFError: Error {
    /// Impossible de construire l'URL de recherche (terme invalide).
    case urlInvalide
    /// Erreur réseau (pas de connexion, timeout, etc.).
    case reseau(any Error)
    /// Réponse HTTP inattendue.
    case statutHTTP(Int)
    /// HTTP 429 — quota dépassé (10 recherches/min/IP côté OFF).
    case rateLimite
    /// Réponse JSON indéchiffrable.
    case decodage(any Error)

    /// Message court affichable à l'utilisateur.
    var messageUtilisateur: String {
        switch self {
        case .rateLimite:
            return "Trop de recherches d'affilée — réessaie dans une minute."
        case .reseau:
            return "Impossible de joindre Open Food Facts. Vérifie ta connexion."
        case .urlInvalide, .statutHTTP, .decodage:
            return "La recherche de produits a échoué. Réessaie plus tard."
        }
    }
}

/// Client de l'API de recherche Open Food Facts (Search-a-licious,
/// `search.openfoodfacts.org`). Recherche texte uniquement — le scan par
/// code-barres viendra plus tard.
///
/// Bonnes pratiques OFF appliquées :
/// - `User-Agent` custom obligatoire (`AppName/Version (contact)`).
/// - Quota recherche : 10 req/min/IP → le déclenchement est explicite côté UI
///   (submit clavier) et un cache mémoire évite les appels répétés.
/// - Pas de clé API ni de secret : appel direct depuis l'iPhone.
final class OpenFoodFactsAPIClient: Sendable {

    static let shared = OpenFoodFactsAPIClient()

    private let session: URLSession
    private let logger = Logger(subsystem: "com.diaviz", category: "OpenFoodFacts")

    private static let baseRecherche = "https://search.openfoodfacts.org/search"
    private static let userAgent = "Diaviz/1.0 (+https://github.com/alexxbout/Diaviz)"

    init(session: URLSession = .shared) {
        self.session = session
    }

    /// Recherche texte de produits, paginée. Renvoie les produits de la page
    /// demandée mappés en `AlimentOFF` (y compris ceux sans glucides
    /// renseignés, signalés à l'affichage — mais pas ceux sans nom
    /// exploitable) et le nombre total de pages.
    func rechercher(
        _ terme: String,
        page: Int = 1,
        parPage: Int = 10
    ) async throws(OFFError) -> PageResultatsOFF {
        var composants = URLComponents(string: Self.baseRecherche)
        composants?.queryItems = [
            URLQueryItem(name: "q", value: terme),
            URLQueryItem(name: "langs", value: "fr"),
            URLQueryItem(name: "page", value: String(page)),
            URLQueryItem(name: "page_size", value: String(parPage)),
            URLQueryItem(name: "fields", value: "code,product_name,product_name_fr,brands,nutriments,image_front_small_url,image_front_url"),
        ]
        guard let url = composants?.url else { throw .urlInvalide }

        var requete = URLRequest(url: url)
        requete.setValue(Self.userAgent, forHTTPHeaderField: "User-Agent")

        let data: Data
        let reponse: URLResponse
        do {
            (data, reponse) = try await session.data(for: requete)
        } catch {
            logger.error("Recherche OFF « \(terme) » — erreur réseau : \(error)")
            throw .reseau(error)
        }

        if let http = reponse as? HTTPURLResponse, http.statusCode != 200 {
            logger.error("Recherche OFF « \(terme) » — HTTP \(http.statusCode)")
            throw http.statusCode == 429 ? .rateLimite : .statutHTTP(http.statusCode)
        }

        do {
            let decodee = try JSONDecoder().decode(ReponseRechercheOFF.self, from: data)
            let produits = decodee.hits.compactMap { $0.versAlimentOFF() }
            logger.info("Recherche OFF « \(terme) » p.\(page) — \(produits.count) produit(s)")
            return PageResultatsOFF(
                produits: produits,
                page: page,
                nombreDePages: decodee.pageCount ?? page
            )
        } catch {
            logger.error("Recherche OFF « \(terme) » — décodage impossible : \(error)")
            throw .decodage(error)
        }
    }
}

/// Une page de résultats de recherche OFF.
struct PageResultatsOFF: Sendable {
    let produits: [AlimentOFF]
    let page: Int
    let nombreDePages: Int
}

// MARK: - Décodage de la réponse Search-a-licious

/// Enveloppe de la réponse `GET /search` de Search-a-licious.
private struct ReponseRechercheOFF: Decodable {
    let hits: [ProduitOFF]
    let pageCount: Int?

    enum CodingKeys: String, CodingKey {
        case hits
        case pageCount = "page_count"
    }
}

/// Un produit brut tel que renvoyé par l'API — mappé ensuite en `AlimentOFF`.
private struct ProduitOFF: Decodable {
    let code: String?
    let productName: String?
    let productNameFr: String?
    let brands: String?
    let nutriments: NutrimentsOFF?
    let imageFrontSmallUrl: String?
    let imageFrontUrl: String?

    enum CodingKeys: String, CodingKey {
        case code
        case productName = "product_name"
        case productNameFr = "product_name_fr"
        case brands
        case nutriments
        case imageFrontSmallUrl = "image_front_small_url"
        case imageFrontUrl = "image_front_url"
    }

    init(from decodeur: any Decoder) throws {
        let conteneur = try decodeur.container(keyedBy: CodingKeys.self)
        code = try conteneur.decodeIfPresent(String.self, forKey: .code)
        productName = try conteneur.decodeIfPresent(String.self, forKey: .productName)
        productNameFr = try conteneur.decodeIfPresent(String.self, forKey: .productNameFr)
        nutriments = try conteneur.decodeIfPresent(NutrimentsOFF.self, forKey: .nutriments)
        imageFrontSmallUrl = try conteneur.decodeIfPresent(String.self, forKey: .imageFrontSmallUrl)
        imageFrontUrl = try conteneur.decodeIfPresent(String.self, forKey: .imageFrontUrl)
        // Search-a-licious renvoie `brands` tantôt en chaîne ("Ferrero"),
        // tantôt en tableau (["Lustucru", "Panzani"]) — on accepte les deux.
        if let chaine = try? conteneur.decodeIfPresent(String.self, forKey: .brands) {
            brands = chaine
        } else if let liste = try? conteneur.decodeIfPresent([String].self, forKey: .brands) {
            brands = liste.joined(separator: ", ")
        } else {
            brands = nil
        }
    }

    /// Mapping vers le modèle app. `nil` si le produit n'a ni code ni nom
    /// exploitable (inutilisable dans une liste de résultats).
    func versAlimentOFF() -> AlimentOFF? {
        guard let code, !code.isEmpty else { return nil }
        let nom = [productNameFr, productName]
            .compactMap { $0?.trimmingCharacters(in: .whitespacesAndNewlines) }
            .first { !$0.isEmpty }
        guard let nom else { return nil }
        return AlimentOFF(
            code: code,
            nom: nom,
            marque: brands?.trimmingCharacters(in: .whitespacesAndNewlines).nilSiVide,
            calories: nutriments?.energyKcal100g,
            glucides: nutriments?.carbohydrates100g,
            sucres: nutriments?.sugars100g,
            proteines: nutriments?.proteins100g,
            lipides: nutriments?.fat100g,
            fibres: nutriments?.fiber100g,
            imagePetiteURL: imageFrontSmallUrl.flatMap(URL.init(string:)),
            imageURL: imageFrontUrl.flatMap(URL.init(string:))
        )
    }
}

private struct NutrimentsOFF: Decodable {
    let energyKcal100g: Double?
    let carbohydrates100g: Double?
    let sugars100g: Double?
    let proteins100g: Double?
    let fat100g: Double?
    let fiber100g: Double?

    enum CodingKeys: String, CodingKey {
        case energyKcal100g = "energy-kcal_100g"
        case carbohydrates100g = "carbohydrates_100g"
        case sugars100g = "sugars_100g"
        case proteins100g = "proteins_100g"
        case fat100g = "fat_100g"
        case fiber100g = "fiber_100g"
    }
}

private extension String {
    var nilSiVide: String? { isEmpty ? nil : self }
}
