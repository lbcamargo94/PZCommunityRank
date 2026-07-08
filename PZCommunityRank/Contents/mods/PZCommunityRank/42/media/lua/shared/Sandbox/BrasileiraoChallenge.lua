-- ============================================================
--  BrasileiraoChallenge.lua — Preset Sandbox do BRASILEIRÃO PZ
--
--  Carregado automaticamente pelo jogo via getSandboxPreset()
--  quando o jogador seleciona o modo BRASILEIRÃO PZ na tela
--  de Nova Partida.
--
--  Valores extraídos do preset oficial "Brasileirão PZ.cfg"
--  e mantidos em sincronia com RankSandbox.lua.
-- ============================================================
return {
    Version = 6,

    -- ── ZUMBIS — População ────────────────────────────────
    ZombieConfig = {
        PopulationMultiplier      = 4.0,
        PopulationStartMultiplier = 2.0,
        PopulationPeakMultiplier  = 2.0,
        PopulationPeakDay         = 1,
        RespawnHours              = 72.0,
        RespawnUnseenHours        = 16.0,
        RespawnMultiplier         = 0.1,
        RedistributeHours         = 12.0,
        FollowSoundDistance       = 100,
        RallyGroupSize            = 1,
        RallyGroupSizeVariance    = 50,
        RallyTravelDistance       = 20,
        RallyGroupSeparation      = 15,
        RallyGroupRadius          = 3,
        ZombiesCountBeforeDelete  = 300,
    },

    -- ── ZUMBIS — Comportamento ────────────────────────────
    ZombieLore = {
        Speed                    = 4,   -- Aleatório
        SprinterPercentage       = 0,   -- Nenhum corredor
        Strength                 = 1,   -- Super-humano
        Toughness                = 1,   -- Resistente
        Transmission             = 1,
        Mortality                = 5,
        Reanimate                = 3,
        Cognition                = 1,   -- Avançado (abre portas)
        DoorOpeningPercentage    = 0,
        CrawlUnderVehicle        = 5,
        Memory                   = 1,   -- Longa
        Sight                    = 1,   -- Águia
        Hearing                  = 1,   -- Alta
        SpottedLogic             = true,
        ThumpNoChasing           = false,
        ThumpOnConstruction      = true,
        ActiveOnly               = 1,
        TriggerHouseAlarm        = true,
        ZombiesDragDown          = true,
        ZombiesCrawlersDragDown  = true,
        ZombiesFenceLunge        = true,
        ZombiesArmorFactor       = 2.0,
        ZombiesMaxDefense        = 85,
        ChanceOfAttachedWeapon   = 6,
        ZombiesFallDamage        = 1.0,
        DisableFakeDead          = 2,   -- Total (incl. mortos pelo jogador)
        PlayerSpawnZombieRemoval = 1,
        FenceThumpersRequired    = 25,
        FenceDamageMultiplier    = 1.0,
    },

    -- ── LOOT — todas as categorias em 0.04 (Muito Baixo) ──
    FoodLootNew          = 0.04,
    LiteratureLootNew    = 0.04,
    SkillBookLoot        = 0.04,
    RecipeResourceLoot   = 0.04,
    MedicalLootNew       = 0.04,
    SurvivalGearsLootNew = 0.04,
    CannedFoodLootNew    = 0.04,
    WeaponLootNew        = 0.04,
    RangedWeaponLootNew  = 0.04,
    AmmoLootNew          = 0.04,
    MechanicsLootNew     = 0.04,
    OtherLootNew         = 0.04,
    ClothingLootNew      = 0.04,
    ContainerLootNew     = 0.04,
    KeyLootNew           = 0.04,
    MediaLootNew         = 0.04,
    MementoLootNew       = 0.04,
    CookwareLootNew      = 0.04,
    MaterialLootNew      = 0.04,
    FarmingLootNew       = 0.04,
    ToolLootNew          = 0.04,
    RollsMultiplier      = 1.0,
    RemoveStoryLoot      = false,
    RemoveZombieLoot     = false,
    ZombiePopLootEffect  = 0,
    InsaneLootFactor     = 0.05,
    ExtremeLootFactor    = 0.2,
    RareLootFactor       = 0.6,
    NormalLootFactor     = 1.0,
    CommonLootFactor     = 2.0,
    AbundantLootFactor   = 3.0,

    -- ── MUNDO ─────────────────────────────────────────────
    Zombies              = 4,
    Distribution         = 1,
    ZombieVoronoiNoise   = true,
    ZombieRespawn        = 4,
    ZombieMigrate        = true,
    DayLength            = 4,
    StartYear            = 1,
    StartMonth           = 7,
    StartDay             = 9,
    StartTime            = 2,
    DayNightCycle        = 1,
    ClimateCycle         = 1,
    FogCycle             = 1,
    WaterShut            = 1,   -- Instantâneo
    ElecShut             = 1,   -- Instantâneo
    WaterShutModifier    = 0,
    ElecShutModifier     = 0,
    AlarmDecay           = 6,   -- 0–5 Anos
    AlarmDecayModifier   = 0,

    -- ── TEMPO / NATUREZA ──────────────────────────────────
    Temperature          = 2,   -- Frio
    Rain                 = 2,   -- Seco
    NightDarkness        = 2,   -- Escuro
    NightLength          = 3,
    ErosionSpeed         = 4,
    ErosionDays          = 0,
    Farming              = 3,
    CompostTime          = 2,
    FishAbundance        = 1,   -- Muito Ruim
    NatureAbundance      = 1,   -- Muito Ruim
    PlantResilience      = 3,
    PlantAbundance       = 3,

    -- ── EVENTOS ───────────────────────────────────────────
    Alarm                = 6,   -- Muito Frequentemente
    LockedHouses         = 6,
    Helicopter           = 2,
    MetaEvent            = 3,   -- Frequentemente
    SleepingEvent        = 1,

    -- ── PERSONAGEM ────────────────────────────────────────
    StarterKit           = false,
    Nutrition            = true,
    StatsDecrease        = 3,
    FoodRotSpeed         = 3,
    FridgeFactor         = 3,
    CharacterFreePoints  = 0,
    ConstructionBonusPoints = 3,
    BoneFracture         = true,
    InjurySeverity       = 2,
    BloodLevel           = 3,
    ClothingDegradation  = 3,
    NegativeTraitsPenalty = 1,
    MuscleStrainFactor   = 0.7,
    DiscomfortFactor     = 0.8,
    WoundInfectionFactor = 1.0,
    EasyClimbing         = false,
    AttackBlockMovements = true,
    MultiHitZombies      = false,
    RearVulnerability    = 3,
    EndRegen             = 3,
    MinutesPerPage       = 2.0,
    LiteratureCooldown   = 45,
    LevelForMediaXPCutoff    = 3,
    LevelForDismantleXPCutoff = 0,

    -- ── MULTIPLICADORES XP ────────────────────────────────
    MultiplierConfig = {
        Global         = 0.8,
        GlobalToggle   = true,
        Fitness        = 1.0,
        Strength       = 1.0,
        Sprinting      = 1.0,
        Lightfoot      = 1.0,
        Nimble         = 1.0,
        Sneak          = 1.0,
        Axe            = 1.0,
        Blunt          = 1.0,
        SmallBlunt     = 1.0,
        LongBlade      = 1.0,
        SmallBlade     = 1.0,
        Spear          = 1.0,
        Maintenance    = 1.0,
        Woodwork       = 1.0,
        Cooking        = 1.0,
        Farming        = 1.0,
        Doctor         = 1.0,
        Electricity    = 1.0,
        MetalWelding   = 1.0,
        Mechanics      = 1.0,
        Tailoring      = 1.0,
        Aiming         = 1.0,
        Reloading      = 1.0,
        Fishing        = 1.0,
        Trapping       = 1.0,
        PlantScavenging = 1.0,
        FlintKnapping  = 1.0,
        Masonry        = 1.0,
        Pottery        = 1.0,
        Carving        = 1.0,
        Husbandry      = 1.0,
        Tracking       = 1.0,
        Blacksmith     = 1.0,
        Butchering     = 1.0,
        Glassmaking    = 1.0,
    },

    -- ── VEÍCULOS ──────────────────────────────────────────
    EnableVehicles       = true,
    CarSpawnRate         = 3,
    ChanceHasGas         = 1,   -- Baixo
    InitialGas           = 1,   -- Muito Baixo
    FuelStationGasInfinite = false,
    FuelStationGasMin    = 0.0,
    FuelStationGasMax    = 0.2,
    FuelStationGasEmptyChance = 50,
    LockedCar            = 6,   -- Muito Frequentemente
    CarGasConsumption    = 1.0,
    CarGeneralCondition  = 1,   -- Muito Baixo
    CarDamageOnImpact    = 3,
    DamageToPlayerFromHitByACar = 1,
    TrafficJam           = true,
    CarAlarm             = 3,
    PlayerDamageFromCrash = true,
    SirenShutoffHours    = 0.0,
    RecentlySurvivorVehicles = 2,
    ZombieAttractionMultiplier = 1.0,
    VehicleEasyUse       = false,
    SirenEffectsZombies  = true,

    -- ── GERADOR / LOOT ESPECIAL ───────────────────────────
    GeneratorFuelConsumption = 0.1,
    GeneratorSpawning    = 1,   -- Extremamente Raro
    GeneratorTileRange   = 20,
    GeneratorVerticalPowerRange = 3,
    AnnotatedMapChance   = 4,

    -- ── ANIMAIS ───────────────────────────────────────────
    AnimalStatsModifier      = 4,
    AnimalMetaStatsModifier  = 4,
    AnimalPregnancyTime      = 4,
    AnimalAgeModifier        = 4,
    AnimalMilkIncModifier    = 4,
    AnimalWoolIncModifier    = 4,
    AnimalRanchChance        = 2,   -- Extremamente Raro
    AnimalGrassRegrowTime    = 240,
    AnimalMetaPredator       = false,
    AnimalMatingSeason       = true,
    AnimalEggHatch           = 4,
    AnimalSoundAttractZombies = true,
    AnimalTrackChance        = 4,
    AnimalPathChance         = 4,

    -- ── AMBIENTE ──────────────────────────────────────────
    FireSpread           = true,
    HoursForCorpseRemoval = 216.0,
    DecayingCorpseHealthImpact = 3,
    ZombieHealthImpact   = false,
    BloodSplatLifespanDays = 0,
    DaysForRottenFoodRemoval = -1,
    AllowExteriorGenerator = true,
    MaxFogIntensity      = 1,
    MaxRainFxIntensity   = 1,
    EnableSnowOnGround   = true,
    SurvivorHouseChance  = 3,
    VehicleStoryChance   = 3,
    ZoneStoryChance      = 3,
    AllClothesUnlocked   = false,
    EnableTaintedWaterText = true,
    HoursForWorldItemRemoval = 24.0,
    ItemRemovalListBlacklistToggle = false,
    WorldItemRemovalList = "Base.Hat, Base.Glasses, Base.Maggots, Base.Slug, Base.Slug2, Base.Snail, Base.Worm, Base.Dung_Mouse, Base.Dung_Rat",
    TimeSinceApo         = 1,
    SeenHoursPreventLootRespawn = 0,
    HoursForLootRespawn  = 0,
    MaxItemsForLootRespawn = 5,
    ConstructionPreventsLootRespawn = true,
    MetaKnowledge        = 3,
    SeeNotLearntRecipe   = true,
    MaximumLootedBuildingRooms = 50,
    EnablePoisoning      = 1,
    MaggotSpawn          = 1,
    LightBulbLifespan    = 2.0,
    NoBlackClothes       = true,
    MaximumFireFuelHours = 8,
    KillInsideCrops      = true,
    PlantGrowingSeasons  = true,
    PlaceDirtAboveground = false,
    FarmingSpeedNew      = 1.0,
    FarmingAmountNew     = 1.0,
    ClayLakeChance       = 0.05,
    ClayRiverChance      = 0.05,
    MaximumRatIndex      = 25,
    DaysUntilMaximumRatIndex = 90,
    MaximumLooted        = 25,
    DaysUntilMaximumLooted = 90,
    RuralLooted          = 0.5,
    MaximumDiminishedLoot = 20,
    DaysUntilMaximumDiminishedLoot = 3650,

    -- ── ARMAS DE FOGO ─────────────────────────────────────
    FirearmUseDamageChance   = 2,
    FirearmNoiseMultiplier   = 1.0,
    FirearmJamMultiplier     = 1.0,
    FirearmMoodleMultiplier  = 1.0,
    FirearmWeatherMultiplier = 1.0,
    FirearmHeadGearEffect    = true,

    -- ── MAPA ──────────────────────────────────────────────
    Map = {
        AllowMiniMap  = true,
        AllowWorldMap = true,
        MapAllKnown   = false,
        MapNeedsLight = true,
    },

    -- ── PORÃO ─────────────────────────────────────────────
    Basement = {
        SpawnFrequency = 4,
    },
}