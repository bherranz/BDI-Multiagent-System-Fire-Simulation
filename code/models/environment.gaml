/**
* Name: Environment and Physics
* Description: Terrain cellular automata, fire propagation and fuel mapping.
*/
model GredosEnvironment

import "parameters.gaml"

// --- CELLULAR AUTOMATION (TERRAIN) ---
grid terrain_cell file: dem_file {
    float altitude <- grid_value;
    bool is_burning <- false;
    bool is_burned  <- false;
    int  fire_duration <- 0;
    float fuel_factor  <- COEF_BASE;

    bool has_road  <- false;
    bool has_water <- false;

    init {
        color <- COLOR_FOREST;
    }

    float compute_slope_effect(terrain_cell target) {
        return (target.altitude - altitude) * slope_influence_factor;
    }

    float compute_wind_effect(terrain_cell target) {
        float angle_to_nb <- location direction_to target.location;
        float wind_alignment <- cos(angle_to_nb - wind_direction);
        return (wind_alignment > 0) ? wind_alignment * wind_intensity * 0.05 : 0.0;
    }

    reflex spread_fire when: is_burning and (every(2 #cycles)) {
        loop nb over: neighbors {
            if (!nb.is_burning and !nb.is_burned) {
                float ignition_probability <- nb.fuel_factor
                    + compute_slope_effect(nb)
                    + compute_wind_effect(nb)
                    + epsilon_base + rnd(-0.01, 0.01);

                ignition_probability <- max(0.0, min(1.0, ignition_probability));

                if (flip(ignition_probability)) {
                    nb.is_burning <- true;
                    nb.color      <- COLOR_BURNING;
                }
            }
        }
    }

    reflex burn_out when: is_burning {
        fire_duration <- fire_duration + 1;
        if (fire_duration > cell_burn_duration) {
            is_burning <- false;
            is_burned  <- true;
            color      <- COLOR_BURNED;
        }
    }
}

// --- GIS AGENTS FOR DATA EXTRACTION ---
species fuel_zone {
    string vegetation_type;
    
    float get_flammability {
        if (vegetation_type contains VEG_FOREST) { return COEF_HIGH; }
        if ((vegetation_type contains VEG_SHRUB) or (vegetation_type contains VEG_SCRUB)) { return COEF_MEDIUM; }
        if ((vegetation_type contains VEG_HERB) or (vegetation_type contains VEG_GRASS)) { return COEF_LOW; }
        if (vegetation_type contains VEG_FIREBREAK) { return COEF_NULL; }
        return COEF_BASE;
    }

    action assign_fuel_to_cells {
        float flammability <- get_flammability();
        ask terrain_cell overlapping self {
            fuel_factor <- flammability;
        }
    }
}