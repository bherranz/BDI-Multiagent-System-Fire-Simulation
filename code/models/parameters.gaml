/**
* Name: Parameters Configuration
* Description: Global constants and simulation parameters for wildfire propagation.
*/

model GredosParameters

global {
    // --- MULTI-AGENT ARCHITECTURE MODE ---
    bool is_centralized_model <- true;

    // --- RECONNAISSANCE DRONE PARAMETERS ---
    int drone_fleet_size <- 15;          // Number of active scouting drones
    float drone_speed <- 120.0;         // Speed in meters/cycle (air flight)
    float drone_max_fuel <- 400.0;      // Maximum flight autonomy (cycles)
    float drone_vision_range <- 400.0;  // Scouting radius in meters (increased for faster detection)
    float drone_wind_tolerance <- 3.5;   // Max wind intensity for safe operation
    float drone_altitude <- 150.0;      // Flight altitude in meters
    
    // --- GROUND FIREFIGHTER (BOMBERO TERRESTRE) PARAMETERS ---
    int firefighter_fleet_size <- 5;            // Number of active ground units
    float firefighter_speed <- 90.0;            // Base speed
    float firefighter_max_water <- 4000.0;      // Maximum water load (liters)
    float firefighter_max_fatigue <- 100.0;     // Fatigue threshold
    float firefighter_max_stress <- 100.0;      // Stress threshold (survival trigger)
    float firefighter_water_use <- 8.0;        // Water use (liters)
    float firefighter_extinction_radius <- 100.0;

    // --- AERIAL FIREFIGHTER (BOMBERO AÉREO / HELICÓPTERO) PARAMETERS ---
    int aerial_firefighter_fleet_size <- 2;    // Number of active helicopters
    float aerial_firefighter_speed <- 150.0;   // Aerial speed (faster, less encumbered)
    float aerial_firefighter_max_water <- 1500.0;     // Water capacity (reduced, from reservoirs)
    float aerial_firefighter_max_fuel <- 500.0;       // Fuel autonomy (critical resource)
    float aerial_firefighter_cruise_altitude <- 200.0; // Flight altitude above terrain
    float aerial_firefighter_max_stress <- 100.0;     // Stress threshold
    float aerial_firefighter_wind_tolerance <- 3.0;   // Max wind speed to operate
    
    int base_capacity <- 2;

    // --- FIRE EVOLUTION PARAMETERS ---
    int cell_burn_duration <- 60;
    float epsilon_base <- 0.01;
	
	// Variables de métricas globales
	int    ciclo_extincion       <- -1;
	int    total_focos_detectados <- 0;
	int    total_evacuaciones     <- 0;
	float  agua_total_terrestre   <- 0.0;
	float  agua_total_aerea       <- 0.0;
	int    burning_count          <- 0;
	int    burned_count           <- 0;
	string escenario_id           <- "TEST-00";
	int    ejecucion_num          <- 1;
	
	// --- LOG FUNCIONAL ---
	list<string> log_buffer <- [];
	string id_prueba <- "PF-001";
	string tipo_ejecucion <- "FUNCIONAL" among: ["FUNCIONAL", "EXPERIMENTAL"];
	
	action log_msg(string msg) {
	    write msg;
	    log_buffer <- log_buffer + [msg];
	}
    
    // --- FUEL MAPPING CONSTANTS (SHP STRINGS) ---
    string VEG_FOREST <- "Bosque";
    string VEG_SCRUB <- "Matorral";
    string VEG_SHRUB <- "Arbustedos";
    string VEG_GRASS <- "Pasto";
    string VEG_HERB <- "Herbazal";
    string VEG_FIREBREAK <- "Cortafuegos";

    // --- FLAMMABILITY COEFFICIENTS ---
    float COEF_HIGH <- 0.06;   // Forest
    float COEF_MEDIUM <- 0.04;  // Scrub and shrubs
    float COEF_LOW <- 0.02;    // Grasslands
    float COEF_NULL <- 0.00;   // Firewalls
    float COEF_BASE <- 0.03;   // Fallback
    
    // --- WIND ADVANCED PARAMETERS ---
    float wind_direction <- 45.0;
    float wind_intensity <- 1.5;
    
    // --- TOPOGRAPHY INFLUENCE PARAMETERS ---
    float slope_influence_factor <- 0.005;
    
    // --- VISUALIZATION CONSTANTS ---
    rgb COLOR_FOREST <- #darkgreen;
    rgb COLOR_BURNING <- #red;
    rgb COLOR_BURNED <- #black;
    rgb COLOR_ROAD <- #purple;
    rgb COLOR_WATER <- #blue;
    rgb COLOR_BASE <- #orange;

    // --- SPATIAL FILES ---
    file dem_file <- file("../includes/dem_gredos.tif");
    shape_file roads_file <- shape_file("../includes/roads.shp");
    shape_file fuel_file <- shape_file("../includes/fuel.shp");
    shape_file water_points_file <- shape_file("../includes/water_points.shp");
    shape_file base_file <- shape_file("../includes/base.shp");
}
