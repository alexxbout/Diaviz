//
//  ArchiveDonneesService.swift
//  diaviz
//

import Foundation
import SwiftData

/// Export / import complet des données de l'app dans un fichier JSON.
///
/// Filet de sécurité indépendant d'iCloud : la synchronisation CloudKit
/// protège contre la perte de l'appareil, pas contre une suppression
/// accidentelle (qui se propage, elle aussi) ni contre un compte iCloud
/// indisponible. Un fichier d'archive sorti de l'app — enregistré dans
/// Fichiers, iCloud Drive, envoyé par AirDrop… — reste lisible et
/// réimportable quoi qu'il arrive au store.
///
/// L'archive couvre **aussi les préférences en `UserDefaults`** (noms et
/// emojis d'aliments personnalisés, aliments cachés, aliments récents avec
/// leurs quantités habituelles, contextes, repas masqués). Celles-ci ne
/// sont pas dans le hub SwiftData, donc jamais synchronisées avec iCloud —
/// sans cette archive, elles sont définitivement perdues à la
/// désinstallation.
enum ArchiveDonneesService {

    /// Version du format. À incrémenter si une évolution casse la lecture
    /// des archives existantes — `importer` refuse ce qu'il ne sait pas lire
    /// plutôt que d'écrire des données à moitié comprises.
    static let versionFormat = 1

    // MARK: - Clés de préférences embarquées

    /// Réglages restés dans `UserDefaults` et malgré tout dignes d'être
    /// archivés. La liste est courte depuis que les préférences d'usage
    /// (renommages, masquages, aliments récents, contextes) sont passées dans
    /// le hub SwiftData : elles sont désormais archivées comme le reste des
    /// données, plus haut.
    ///
    /// Les clés purement techniques ou propres à l'appareil (ancre HealthKit,
    /// session sportive en cours, drapeaux de démarrage) restent exclues :
    /// elles n'ont aucun sens sur un autre appareil ou après restauration, et
    /// seraient nuisibles à réimporter.
    private static let clesPreferences = [
        "healthkit.sport.ignores",
    ]

    // MARK: - Export

    @MainActor
    static func exporter(contexte: ModelContext) throws -> Data {
        func tout<T: PersistentModel>(_ type: T.Type) -> [T] {
            (try? contexte.fetch(FetchDescriptor<T>())) ?? []
        }

        let archive = Archive(
            version: versionFormat,
            dateExport: Date(),
            profil: ProfilService.shared.profil.estValide
                ? ProfilArchive(ProfilService.shared.profil)
                : nil,
            repas: tout(Repas.self).map(RepasArchive.init),
            injections: tout(Injection.self).map(InjectionArchive.init),
            activites: tout(ActiviteSportive.self).map(ActiviteArchive.init),
            resucrages: tout(Resucrage.self).map(ResucrageArchive.init),
            etats: tout(EtatDeclare.self).map(EtatArchive.init),
            medicaments: tout(Medicament.self).map(MedicamentArchive.init),
            pauses: tout(PeriodePause.self).map(PauseArchive.init),
            glycemies: tout(GlucoseReading.self).map(GlycemieArchive.init),
            preferencesAliments: tout(PreferenceAlimentCiqual.self).map(PreferenceAlimentArchive.init),
            alimentsRecents: tout(AlimentRecentEnregistre.self).map(AlimentRecentArchive.init),
            contextes: tout(ContexteNormaliseEnregistre.self).map(ContexteArchive.init),
            repasMasques: tout(RepasARevoirMasque.self).map(\.idRepas),
            preferences: preferencesActuelles()
        )

        let encodeur = JSONEncoder()
        encodeur.dateEncodingStrategy = .iso8601
        encodeur.outputFormatting = [.prettyPrinted, .sortedKeys]
        return try encodeur.encode(archive)
    }

    /// Nom de fichier horodaté — lisible et triable.
    static func nomFichierExport(date: Date = Date()) -> String {
        let format = DateFormatter()
        format.dateFormat = "yyyy-MM-dd-HHmm"
        format.locale = Locale(identifier: "fr_FR")
        return "Diaviz-\(format.string(from: date)).json"
    }

    // MARK: - Import

    /// Remplace **intégralement** le contenu du hub par celui de l'archive.
    ///
    /// Remplacement et non fusion : réimporter par-dessus des données
    /// existantes produirait des doublons impossibles à démêler (rien ne
    /// distingue un repas réimporté d'un repas ressaisi). L'appelant doit
    /// avoir fait confirmer l'écrasement.
    ///
    /// Les suppressions passent par `SuppressionDonneesService`, donc objet
    /// par objet : elles sont ainsi exportées vers iCloud, tout comme les
    /// insertions qui suivent. L'archive réimportée se resynchronise donc
    /// d'elle-même, sans manipulation supplémentaire.
    @MainActor
    static func importer(_ data: Data, contexte: ModelContext) throws {
        let decodeur = JSONDecoder()
        decodeur.dateDecodingStrategy = .iso8601
        let archive = try decodeur.decode(Archive.self, from: data)

        guard archive.version <= versionFormat else {
            throw ErreurArchive.versionTropRecente(archive.version)
        }

        SuppressionDonneesService.supprimerTout(contexte: contexte)

        for element in archive.preferencesAliments { contexte.insert(element.versModele()) }
        for element in archive.alimentsRecents { contexte.insert(element.versModele()) }
        for element in archive.contextes { contexte.insert(element.versModele()) }
        for identifiant in archive.repasMasques {
            contexte.insert(RepasARevoirMasque(idRepas: identifiant))
        }
        for element in archive.repas { contexte.insert(element.versModele()) }
        for element in archive.injections { contexte.insert(element.versModele()) }
        for element in archive.activites { contexte.insert(element.versModele()) }
        for element in archive.resucrages { contexte.insert(element.versModele()) }
        for element in archive.etats { contexte.insert(element.versModele()) }
        for element in archive.medicaments { contexte.insert(element.versModele()) }
        for element in archive.pauses { contexte.insert(element.versModele()) }
        for element in archive.glycemies { contexte.insert(element.versModele()) }

        if let profil = archive.profil {
            let modele = profil.versModele()
            contexte.insert(modele)
        }

        try contexte.save()

        restaurerPreferences(archive.preferences)

        // Les services tiennent leur état en mémoire et pointent encore sur
        // les lignes supprimées : on les fait relire le store fraîchement
        // importé, sans quoi l'app afficherait l'ancien contenu jusqu'au
        // prochain lancement.
        ProfilService.shared.rafraichirDepuisCloudKit()
        NomsPersonnalisesService.shared.recharger()
        AlimentsCachesService.shared.recharger()
        AlimentsRecentsService.shared.recharger()
        RepasARevoirMasquesService.shared.recharger()
        ReferentielContextesService.shared.recharger()
    }

    enum ErreurArchive: LocalizedError {
        case versionTropRecente(Int)

        var errorDescription: String? {
            switch self {
            case .versionTropRecente(let version):
                "Cette archive (format v\(version)) a été créée par une version plus récente de Diaviz."
            }
        }
    }

    // MARK: - Préférences UserDefaults

    /// Sérialise les préférences retenues en `Data` (format property list),
    /// ce qui préserve leurs types d'origine — tableaux, dictionnaires,
    /// blobs JSON — sans avoir à connaître la forme de chacune.
    private static func preferencesActuelles() -> [String: Data] {
        var resultat: [String: Data] = [:]
        for cle in clesPreferences {
            guard let valeur = UserDefaults.standard.object(forKey: cle) else { continue }
            guard let data = try? PropertyListSerialization.data(
                fromPropertyList: valeur, format: .binary, options: 0
            ) else { continue }
            resultat[cle] = data
        }
        return resultat
    }

    private static func restaurerPreferences(_ preferences: [String: Data]) {
        for (cle, data) in preferences {
            guard clesPreferences.contains(cle) else { continue }
            guard let valeur = try? PropertyListSerialization.propertyList(
                from: data, options: [], format: nil
            ) else { continue }
            UserDefaults.standard.set(valeur, forKey: cle)
        }
    }
}

// MARK: - Format d'archive

private struct Archive: Codable {
    var version: Int
    var dateExport: Date
    var profil: ProfilArchive?
    var repas: [RepasArchive]
    var injections: [InjectionArchive]
    var activites: [ActiviteArchive]
    var resucrages: [ResucrageArchive]
    var etats: [EtatArchive]
    var medicaments: [MedicamentArchive]
    var pauses: [PauseArchive]
    var glycemies: [GlycemieArchive]
    var preferencesAliments: [PreferenceAlimentArchive]
    var alimentsRecents: [AlimentRecentArchive]
    var contextes: [ContexteArchive]
    var repasMasques: [UUID]
    var preferences: [String: Data]

    /// Champs ajoutés après la v1 du format : absents des archives déjà
    /// produites, ils doivent se décoder en liste vide plutôt que de faire
    /// échouer l'import entier.
    enum CodingKeys: String, CodingKey {
        case version, dateExport, profil, repas, injections, activites
        case resucrages, etats, medicaments, pauses, glycemies
        case preferencesAliments, alimentsRecents, contextes, repasMasques
        case preferences
    }

    init(
        version: Int,
        dateExport: Date,
        profil: ProfilArchive?,
        repas: [RepasArchive],
        injections: [InjectionArchive],
        activites: [ActiviteArchive],
        resucrages: [ResucrageArchive],
        etats: [EtatArchive],
        medicaments: [MedicamentArchive],
        pauses: [PauseArchive],
        glycemies: [GlycemieArchive],
        preferencesAliments: [PreferenceAlimentArchive],
        alimentsRecents: [AlimentRecentArchive],
        contextes: [ContexteArchive],
        repasMasques: [UUID],
        preferences: [String: Data]
    ) {
        self.version = version
        self.dateExport = dateExport
        self.profil = profil
        self.repas = repas
        self.injections = injections
        self.activites = activites
        self.resucrages = resucrages
        self.etats = etats
        self.medicaments = medicaments
        self.pauses = pauses
        self.glycemies = glycemies
        self.preferencesAliments = preferencesAliments
        self.alimentsRecents = alimentsRecents
        self.contextes = contextes
        self.repasMasques = repasMasques
        self.preferences = preferences
    }

    init(from decodeur: Decoder) throws {
        let valeurs = try decodeur.container(keyedBy: CodingKeys.self)
        version = try valeurs.decode(Int.self, forKey: .version)
        dateExport = try valeurs.decode(Date.self, forKey: .dateExport)
        profil = try valeurs.decodeIfPresent(ProfilArchive.self, forKey: .profil)
        repas = try valeurs.decodeIfPresent([RepasArchive].self, forKey: .repas) ?? []
        injections = try valeurs.decodeIfPresent([InjectionArchive].self, forKey: .injections) ?? []
        activites = try valeurs.decodeIfPresent([ActiviteArchive].self, forKey: .activites) ?? []
        resucrages = try valeurs.decodeIfPresent([ResucrageArchive].self, forKey: .resucrages) ?? []
        etats = try valeurs.decodeIfPresent([EtatArchive].self, forKey: .etats) ?? []
        medicaments = try valeurs.decodeIfPresent([MedicamentArchive].self, forKey: .medicaments) ?? []
        pauses = try valeurs.decodeIfPresent([PauseArchive].self, forKey: .pauses) ?? []
        glycemies = try valeurs.decodeIfPresent([GlycemieArchive].self, forKey: .glycemies) ?? []
        preferencesAliments = try valeurs.decodeIfPresent(
            [PreferenceAlimentArchive].self, forKey: .preferencesAliments
        ) ?? []
        alimentsRecents = try valeurs.decodeIfPresent(
            [AlimentRecentArchive].self, forKey: .alimentsRecents
        ) ?? []
        contextes = try valeurs.decodeIfPresent([ContexteArchive].self, forKey: .contextes) ?? []
        repasMasques = try valeurs.decodeIfPresent([UUID].self, forKey: .repasMasques) ?? []
        preferences = try valeurs.decodeIfPresent([String: Data].self, forKey: .preferences) ?? [:]
    }
}

private struct PreferenceAlimentArchive: Codable {
    var idCiqual: Int
    var nomPersonnalise: String?
    var emojiPersonnalise: String?
    var masque: Bool

    init(_ modele: PreferenceAlimentCiqual) {
        idCiqual = modele.idCiqual
        nomPersonnalise = modele.nomPersonnalise
        emojiPersonnalise = modele.emojiPersonnalise
        masque = modele.masque
    }

    func versModele() -> PreferenceAlimentCiqual {
        PreferenceAlimentCiqual(
            idCiqual: idCiqual,
            nomPersonnalise: nomPersonnalise,
            emojiPersonnalise: emojiPersonnalise,
            masque: masque
        )
    }
}

private struct AlimentRecentArchive: Codable {
    var cle: String
    var rang: Int
    var quantite: Double?
    var taillePortion: Double?
    var modeQuantite: String?
    var snapshot: Data?

    init(_ modele: AlimentRecentEnregistre) {
        cle = modele.cle
        rang = modele.rang
        quantite = modele.quantite
        taillePortion = modele.taillePortion
        modeQuantite = modele.modeQuantite
        snapshot = modele.snapshot
    }

    func versModele() -> AlimentRecentEnregistre {
        AlimentRecentEnregistre(
            cle: cle,
            rang: rang,
            quantite: quantite,
            taillePortion: taillePortion,
            modeQuantite: modeQuantite,
            snapshot: snapshot
        )
    }
}

private struct ContexteArchive: Codable {
    var identifiant: UUID
    var libelle: String
    var emoji: String
    var variantes: [String]
    var rang: Int

    init(_ modele: ContexteNormaliseEnregistre) {
        identifiant = modele.identifiant
        libelle = modele.libelle
        emoji = modele.emoji
        variantes = modele.variantes
        rang = modele.rang
    }

    func versModele() -> ContexteNormaliseEnregistre {
        ContexteNormaliseEnregistre(
            identifiant: identifiant,
            libelle: libelle,
            emoji: emoji,
            variantes: variantes,
            rang: rang
        )
    }
}

private struct AlimentArchive: Codable {
    var id: UUID
    var emoji: String
    var nom: String
    var quantite: Int
    var glucides: Int
    var insuline: Double
    var imageURL: URL?
    var resucrage: Bool
    var idCiqualSource: Int?

    init(_ modele: Aliment) {
        id = modele.id
        emoji = modele.emoji
        nom = modele.nom
        quantite = modele.quantite
        glucides = modele.glucides
        insuline = modele.insuline
        imageURL = modele.imageURL
        resucrage = modele.resucrage
        idCiqualSource = modele.idCiqualSource
    }

    /// Toujours une instance neuve par parent : `Aliment` porte des
    /// relations à inverse déclaré, et SwiftData n'autorise qu'un parent à
    /// la fois — partager une instance la volerait au parent précédent.
    func versModele() -> Aliment {
        Aliment(
            id: id,
            emoji: emoji,
            nom: nom,
            quantite: quantite,
            glucides: glucides,
            insuline: insuline,
            imageURL: imageURL,
            resucrage: resucrage,
            idCiqualSource: idCiqualSource
        )
    }
}

private struct RepasArchive: Codable {
    var id: UUID
    var heure: Date
    var aliments: [AlimentArchive]
    var iobAuDebut: Double?
    var doseGlobale: Double?
    var doseCorrection: Double?
    var verdictPersiste: VerdictGlycemique?
    /// Optionnel avec valeur par défaut : les archives écrites avant l'ajout
    /// du champ se réimportent sans erreur de décodage.
    var raisonMauvaisPersistee: RaisonMauvaisVerdict? = nil
    var ratioEffectifPersiste: Double?
    var ajustements: [Ajustement]
    var contexteLibre: String?
    var contexteNormalise: String?
    var exclureDesAnalyses: Bool

    init(_ modele: Repas) {
        id = modele.id
        heure = modele.heure
        aliments = modele.aliments.map(AlimentArchive.init)
        iobAuDebut = modele.iobAuDebut
        doseGlobale = modele.doseGlobale
        doseCorrection = modele.doseCorrection
        verdictPersiste = modele.verdictPersiste
        raisonMauvaisPersistee = modele.raisonMauvaisPersistee
        ratioEffectifPersiste = modele.ratioEffectifPersiste
        ajustements = modele.ajustements
        contexteLibre = modele.contexteLibre
        contexteNormalise = modele.contexteNormalise
        exclureDesAnalyses = modele.exclureDesAnalyses
    }

    func versModele() -> Repas {
        let repas = Repas(
            id: id,
            heure: heure,
            aliments: aliments.map { $0.versModele() },
            iobAuDebut: iobAuDebut,
            doseGlobale: doseGlobale,
            doseCorrection: doseCorrection,
            verdictPersiste: verdictPersiste,
            raisonMauvaisPersistee: raisonMauvaisPersistee,
            ratioEffectifPersiste: ratioEffectifPersiste,
            ajustements: ajustements,
            contexteLibre: contexteLibre,
            contexteNormalise: contexteNormalise,
            exclureDesAnalyses: exclureDesAnalyses
        )
        return repas
    }
}

private struct InjectionArchive: Codable {
    var id: UUID
    var type: TypeInsuline
    var dose: Double
    var heure: Date
    var zoneInjection: ZoneInjection
    var coteInjection: CoteInjection
    var note: String?
    var glycemieAuMoment: Double?
    var repasAssocieId: UUID?
    var nomMedicament: String?
    var labelRepas: String?
    var emojiRepas: String?
    var motif: MotifInjection?
    var source: SourceDonnee

    init(_ modele: Injection) {
        id = modele.id
        type = modele.type
        dose = modele.dose
        heure = modele.heure
        zoneInjection = modele.zoneInjection
        coteInjection = modele.coteInjection
        note = modele.note
        glycemieAuMoment = modele.glycemieAuMoment
        repasAssocieId = modele.repasAssocieId
        nomMedicament = modele.nomMedicament
        labelRepas = modele.labelRepas
        emojiRepas = modele.emojiRepas
        motif = modele.motif
        source = modele.source
    }

    func versModele() -> Injection {
        Injection(
            id: id,
            type: type,
            dose: dose,
            heure: heure,
            zoneInjection: zoneInjection,
            coteInjection: coteInjection,
            note: note,
            glycemieAuMoment: glycemieAuMoment,
            repasAssocieId: repasAssocieId,
            nomMedicament: nomMedicament,
            labelRepas: labelRepas,
            emojiRepas: emojiRepas,
            motif: motif,
            source: source
        )
    }
}

private struct ActiviteArchive: Codable {
    var id: UUID
    var type: TypeSport
    var dateDebut: Date
    var dureeMinutes: Int
    var intensite: IntensiteSport
    var alimentsPreSport: [AlimentArchive]
    var structureEffort: StructureEffort?
    var pauses: [IntervallePauseSeance]
    var note: String?
    var source: SourceActivite
    var healthKitData: HealthKitWorkoutData?
    var iobAuDebut: Double?

    init(_ modele: ActiviteSportive) {
        id = modele.id
        type = modele.type
        dateDebut = modele.dateDebut
        dureeMinutes = modele.dureeMinutes
        intensite = modele.intensite
        alimentsPreSport = modele.alimentsPreSport.map(AlimentArchive.init)
        structureEffort = modele.structureEffort
        pauses = modele.pauses
        note = modele.note
        source = modele.source
        healthKitData = modele.healthKitData
        iobAuDebut = modele.iobAuDebut
    }

    func versModele() -> ActiviteSportive {
        ActiviteSportive(
            id: id,
            type: type,
            dateDebut: dateDebut,
            dureeMinutes: dureeMinutes,
            intensite: intensite,
            alimentsPreSport: alimentsPreSport.map { $0.versModele() },
            structureEffort: structureEffort,
            pauses: pauses,
            note: note,
            source: source,
            healthKitData: healthKitData,
            iobAuDebut: iobAuDebut
        )
    }
}

private struct ResucrageArchive: Codable {
    var id: UUID
    var date: Date
    var intention: IntentionResucrage
    var aliments: [AlimentArchive]
    var glycemieCible: Double?

    init(_ modele: Resucrage) {
        id = modele.id
        date = modele.date
        intention = modele.intention
        aliments = modele.aliments.map(AlimentArchive.init)
        glycemieCible = modele.glycemieCible
    }

    func versModele() -> Resucrage {
        Resucrage(
            id: id,
            date: date,
            intention: intention,
            aliments: aliments.map { $0.versModele() },
            glycemieCible: glycemieCible
        )
    }
}

private struct EtatArchive: Codable {
    var date: Date
    var type: TypeEtat
    var intensite: Int?
    var note: String?

    init(_ modele: EtatDeclare) {
        date = modele.date
        type = modele.type
        intensite = modele.intensite
        note = modele.note
    }

    func versModele() -> EtatDeclare {
        EtatDeclare(date: date, type: type, intensite: intensite, note: note)
    }
}

private struct MedicamentArchive: Codable {
    var date: Date
    var nom: String
    var dose: String?
    var recurrent: Bool
    var note: String?

    init(_ modele: Medicament) {
        date = modele.date
        nom = modele.nom
        dose = modele.dose
        recurrent = modele.recurrent
        note = modele.note
    }

    func versModele() -> Medicament {
        Medicament(date: date, nom: nom, dose: dose, recurrent: recurrent, note: note)
    }
}

private struct PauseArchive: Codable {
    var debut: Date
    var fin: Date?
    var motif: MotifPause
    var note: String?

    init(_ modele: PeriodePause) {
        debut = modele.debut
        fin = modele.fin
        motif = modele.motif
        note = modele.note
    }

    func versModele() -> PeriodePause {
        PeriodePause(debut: debut, fin: fin, motif: motif, note: note)
    }
}

private struct GlycemieArchive: Codable {
    var date: Date
    var valeur: Int
    var tendance: TendanceGlycemie?
    var tauxVariation: Double?
    var source: SourceDonnee

    init(_ modele: GlucoseReading) {
        date = modele.date
        valeur = modele.valeur
        tendance = modele.tendance
        tauxVariation = modele.tauxVariation
        source = modele.source
    }

    func versModele() -> GlucoseReading {
        GlucoseReading(
            date: date,
            valeur: valeur,
            tendance: tendance,
            tauxVariation: tauxVariation,
            source: source
        )
    }
}

private struct ProfilArchive: Codable {
    var prenom: String
    var photoData: Data?
    var poidsKg: Double?
    var insulineRapide: InsulineRapide
    var insulineLente: InsulineLente
    var dureeActionInsulineHeures: Double
    var intervalleMinimumLenteHeures: Double?
    var modeRatio: ModeRatio
    var ratioUnique: Double?
    var ratiosParMoment: RatiosParMoment
    var datesChangementRatio: DatesChangementRatio?
    var ratioCorrection: Double?
    var ratiosSport: RatiosSport?
    var horairesRepas: HorairesRepas
    var seuilsGlycemiques: SeuilsGlycemiques
    var preferencesAvancees: PreferencesAvancees

    init(_ modele: ProfilUtilisateur) {
        prenom = modele.prenom
        photoData = modele.photoData
        poidsKg = modele.poidsKg
        insulineRapide = modele.insulineRapide
        insulineLente = modele.insulineLente
        dureeActionInsulineHeures = modele.dureeActionInsulineHeures
        intervalleMinimumLenteHeures = modele.intervalleMinimumLenteHeures
        modeRatio = modele.modeRatio
        ratioUnique = modele.ratioUnique
        ratiosParMoment = modele.ratiosParMoment
        datesChangementRatio = modele.datesChangementRatio
        ratioCorrection = modele.ratioCorrection
        ratiosSport = modele.ratiosSport
        horairesRepas = modele.horairesRepas
        seuilsGlycemiques = modele.seuilsGlycemiques
        preferencesAvancees = modele.preferencesAvancees
    }

    func versModele() -> ProfilUtilisateur {
        ProfilUtilisateur(
            prenom: prenom,
            photoData: photoData,
            poidsKg: poidsKg,
            insulineRapide: insulineRapide,
            insulineLente: insulineLente,
            dureeActionInsulineHeures: dureeActionInsulineHeures,
            intervalleMinimumLenteHeures: intervalleMinimumLenteHeures,
            modeRatio: modeRatio,
            ratioUnique: ratioUnique,
            ratiosParMoment: ratiosParMoment,
            datesChangementRatio: datesChangementRatio,
            ratioCorrection: ratioCorrection,
            ratiosSport: ratiosSport,
            horairesRepas: horairesRepas,
            seuilsGlycemiques: seuilsGlycemiques,
            preferencesAvancees: preferencesAvancees
        )
    }
}
