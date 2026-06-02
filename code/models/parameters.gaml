/**
* Name: Parameters Configuration
* Description: Global constants and simulation parameters for wildfire propagation.
*/

model GredosParameters

global {
    // --- FIRE EVOLUTION PARAMETERS ---
    int cell_burn_duration <- 30;
    float epsilon_base <- 0.01;
    
    // --- FUEL MAPPING CONSTANTS (SHP STRINGS) ---
    string VEG_FOREST <- "Bosque";
    string VEG_SCRUB <- "Matorral";
    string VEG_SHRUB <- "Arbustedos";
    string VEG_GRASS <- "Pasto";
    string VEG_HERB <- "Herbazal";
    string VEG_FIREBREAK <- "Cortafuegos";

    // --- FLAMMABILITY COEFFICIENTS ---
    float COEF_HIGH <- 0.08;   // Dense forest
    float COEF_MEDIUM <- 0.05; // Scrub and shrubs
    float COEF_LOW <- 0.03;    // Grasslands
    float COEF_NULL <- 0.00;   // Firewalls
    float COEF_BASE <- 0.04;   // Fallback
    
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