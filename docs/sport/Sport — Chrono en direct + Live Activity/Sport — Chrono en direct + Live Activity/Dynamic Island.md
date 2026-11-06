# Sport — Chrono en direct + Live Activity / Dynamic Island
Permet de démarrer une séance sportive chronométrée en direct (au lieu de la seule saisie rétrospective), avec Pause/Reprise/Terminer, et un suivi via Live Activity (Dynamic Island + écran verrouillé).

**Statut** : ✅ Implémenté et mergé sur `main` 

**V1 minimale** : chrono + type de sport uniquement, PAS de glycémie live.

---

## Parcours utilisateur
### Point d'entrée
- Sheet **« Nouvelle activité »** (`SheetNouvelleActivite`  ) avec un sélecteur segmenté :
    - **Chrono en direct** / **Saisie manuelle**

- En mode direct :
    - Choix du type de sport
    - Bouton **« Démarrer :  »**

### Séance en cours
- Écran plein écran (`SeanceEnCoursVue`  ) :
    - Chrono count-up
    - Badge statut **En cours** / **En pause**
    - Boutons **Pause·Reprendre** / **Terminer**
    - Bouton **Annuler** (abandon sans enregistrer)

### Arrêt
- Bascule sur la sheet d'enregistrement pré-remplie :
    - Durée chronométrée déjà remplie
    - Intensité par défaut **Modérée** (à confirmer)

- La glycémie début/fin reste calculée après coup depuis le CGM du hub (assembleur du détail d'activité)
---

## Modèle & persistance
### `SessionSportiveEnCours` 
**Emplacement** : `Diaviz/modeles/sport/` 

- Struct `Codable`  / `Identifiable`  de la séance active
- Temps d'effort réel déduit des horodatages :
    - `dateDebut`  
    - `secondesPauseCumulees`  
    - `debutPauseCourante` 

- Pas de timer en tâche de fond
- `dateReference`  = début décalé du temps de pause cumulé (pour timer count-up)
- **Persistée en UserDefaults** → survit au kill/relaunch de l'app
### `SessionSportService` 
**Emplacement** : `Diaviz/services/sport/` 

- Singleton `@MainActor`  `@Observable`  
- Façade applicative avec méthodes :
    - `demarrer()`  / `pause()`  / `reprendre()`  / `terminer()`  / `annuler()`  
    - `reconcilier()`  — réconciliation au premier plan

---

## Live Activity / Dynamic Island (ActivityKit)
### Configuration
| Élément | Valeur |
| ----- | ----- |
| Cible widget extension | `DiavizSportWidget`  |
| Bundle ID | `fr.al3xdre.diaviz.DiavizSportWidget`  |
| Info.plist app | `NSSupportsLiveActivities = YES`  |
### `ActiviteSportiveAttributes` 
**Fichier PARTAGÉ app ↔ widget**

- **Attributs statiques** :
    - `typeLabel`  
    - `iconeSF`  
    - `dateDebut` 

- **ContentState dynamique** :
    - `enPause`  
    - `dateReference`  
    - `secondesFigees` 

>   Volontairement sans dépendance métier lourde.  

### `SeanceSportiveLiveActivity` 
**Emplacement** : `DiavizSportWidget/` 

| Mode | Contenu |
| ----- | ----- |
| **Compact** | Icône + chrono |
| **Étendu** | Icône, chrono + « démarré à », titre en grand, badge statut, boutons Pause/Terminer |
| **Minimal** | Vue réduite |
| **Bannière écran verrouillé** | Affichage sur lock screen |
- Chrono count-up piloté système : `Text(dateReference, style: .timer)`  
- Valeur figée en pause
### Boutons interactifs
- Implémentés via `LiveActivityIntent`  :
    - `BasculerPauseSeanceIntent`  
    - `TerminerSeanceIntent` 

- Fichier partagé entre app et widget
- `perform()`  s'exécute dans le process de l'app et passe par `ControleurSeanceLive` 
---

## Architecture de partage app ↔ widget
### Contrainte
Le type des intents doit compiler côté widget (pour `Button(intent:)`), mais leur logique tourne côté app.

### Solution : `ControleurSeanceLive` 
Couche partagée **sans SwiftData ni** `**@Observable**` qui manipule uniquement :

- La `SessionSportiveEnCours`  persistée (UserDefaults)
- La Live Activity (ActivityKit)
### Flux de synchronisation
1. Les boutons de l'île mutent la séance persistée + la Live Activity
2. Au retour au premier plan, `SessionSportService.reconcilier()`  :
    - Resynchronise l'état observable (ex: pause faite depuis l'île)
    - Récupère un snapshot de séance terminée depuis l'île pour ouvrir l'enregistrement pré-rempli

### Fichiers rattachés aux DEUX cibles (Target Membership)
- `ActiviteSportiveAttributes`  
- `SessionSportiveEnCours`  
- `TypeSport`  
- `CategorieSport`  
- `ControleurSeanceLive`  
- `SeanceLiveActivityIntents` 
---

## Contraintes / notes
- **HealthKit-style** : la Live Activity ne s'affiche que sur device réel, et si les Activités en direct sont autorisées (Réglages → Diaviz)
- Le chrono conserve un **format unifié** : `m:ss`  puis `h:mm:ss`  (en cours comme en pause)
- **V1 volontairement sans glycémie live** (délai des données CGM) — la corrélation glycémique se fait après coup sur le détail de la séance enregistrée
---

## Fichiers clés
### Modèles
- `Diaviz/modeles/sport/SessionSportiveEnCours.swift`  
- `Diaviz/modeles/sport/ActiviteSportiveAttributes.swift` 
### Services
- `Diaviz/services/sport/SessionSportService.swift`  
- `Diaviz/services/sport/ControleurSeanceLive.swift`  
- `Diaviz/services/sport/SeanceLiveActivityIntents.swift` 
### Vues
- `Diaviz/vues/sport/SeanceEnCoursVue.swift`  
- `Diaviz/vues/sport/SportVue.swift`  
- `Diaviz/vues/sport/Sheets/SheetNouvelleActivite.swift` 
### Widget extension
- `DiavizSportWidget/SeanceSportiveLiveActivity.swift`  
- `DiavizSportWidget/DiavizSportWidgetBundle.swift`
