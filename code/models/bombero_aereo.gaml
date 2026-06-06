/**
* Name: Aerial Firefighter Agent (Bombero Aéreo)
* Description: BDI cognitive definition for the helicopter unit.
* Features: High mobility, inaccessible zone support, direct fire attack
*/

model GredosBomberoAereo

import "parameters.gaml"
import "environment.gaml"
import "infrastructure.gaml"
import "main.gaml"

species bombero_aereo control: simple_bdi skills: [moving] {

    // --- ONTOLOGICAL ATTRIBUTES ---
    float water_load        <- aerial_firefighter_max_water;
    float fuel_level        <- aerial_firefighter_max_fuel;
    float stress_level      <- 0.0;
    float wind_exposure     <- 0.0;
    string operational_state <- "Disponible"; // Disponible | En vuelo | Extinguiendo | Repostando | Recargando agua

    // Target assigned by Coordinator (Protocol 2)
    point assigned_target_location <- nil;

    // --- BDI PREDICATES ---
    string EXTINGUISH_DESIRE     <- "extinguish_fire_aerial";
    string REFUEL_FUEL_DESIRE    <- "recharge_fuel";
    string REFUEL_WATER_DESIRE   <- "recharge_water";
    string SURVIVAL_DESIRE       <- "self_protection";

    // --- VISUAL ASPECT ---
    aspect default {
        draw line([{location.x, location.y, location.z},
                   {location.x, location.y, location.z - 100.0}])
             color: #yellow width: 2;
        draw sphere(60.0) color: #yellow border: #orange;
    }

    // --- INITIALISATION ---
    init {
        speed <- aerial_firefighter_speed;
        water_load <- aerial_firefighter_max_water;
        fuel_level <- aerial_firefighter_max_fuel;
    }

    // --- COGNITIVE ACTIONS ---

    // Protocol 2: Evaluate and respond to mission request from Coordinator
    action request_mission(point target_location) {
        // Evaluate BDI state: water, fuel, wind
        float water_margin <- water_load - (aerial_firefighter_max_water * 0.2);
        float fuel_margin <- fuel_level - (aerial_firefighter_max_fuel * 0.25); // Need 25% to return to base
        float wind_margin <- aerial_firefighter_wind_tolerance - wind_intensity;
        float stress_margin <- aerial_firefighter_max_stress - stress_level;

        bool can_accept <- (water_margin > 0 and fuel_margin > 0 and wind_margin > 0.5 and stress_margin > 15.0);

        if (can_accept) {
            write "🚁 Helicóptero [" + name + "]: AGREE — Accepting aerial mission at " + target_location;
            assigned_target_location <- target_location;
            do add_desire(predicate(EXTINGUISH_DESIRE), 4.5);
        } else {
            write "🔴 Helicóptero [" + name + "]: REFUSE — Cannot accept mission (water: " + water_load + 
                  ", fuel: " + fuel_level + ", wind: " + wind_intensity + ")";
        }
    }

    // --- REFLEXES ---

    reflex adjust_altitude_to_terrain {
        // Helicopters maintain altitude ABOVE terrain
        terrain_cell current_cell <- terrain_cell(location);
        if (current_cell != nil) {
            float min_altitude <- current_cell.altitude + aerial_firefighter_cruise_altitude;
            location <- {location.x, location.y, min_altitude};
        }
    }

    reflex consume_fuel {
        // Fuel consumption: 2.0 per cycle during flight operations
        if (operational_state != "Disponible" and operational_state != "Repostando") {
            fuel_level <- max(0.0, fuel_level - 2.0);
        }
    }

    reflex wind_exposure_check {
        // Check if wind is too strong
        if (wind_intensity > aerial_firefighter_wind_tolerance) {
            wind_exposure <- wind_exposure + 1.0;
            write "⚠️ Helicóptero [" + name + "]: Strong wind (" + wind_intensity + "). Exposure: " + int(wind_exposure);
            
            if (wind_exposure > 10.0 and !has_desire(predicate(SURVIVAL_DESIRE))) {
                do add_desire(predicate(SURVIVAL_DESIRE), 5.5);
                write "🌪️ Helicóptero [" + name + "]: WIND CRITICAL. Returning to base for shelter.";
            }
        } else {
            wind_exposure <- max(0.0, wind_exposure - 0.3);
        }
    }

    reflex evaluate_stress {
        if (operational_state = "Extinguiendo") {
            stress_level <- stress_level + 0.3;
        } else if (operational_state = "Disponible" and stress_level > 0) {
            stress_level <- stress_level - 0.2;
        }

        geometry danger_zone <- circle(200.0) at_location {location.x, location.y};
        list<terrain_cell> nearby_fire <- (terrain_cell overlapping danger_zone) where (each.is_burning);

        if (!empty(nearby_fire)) {
            stress_level <- stress_level + (length(nearby_fire) * 0.15);
        } else {
            stress_level <- max(0.0, stress_level - 0.2);
        }

        if (stress_level > aerial_firefighter_max_stress and !has_desire(predicate(SURVIVAL_DESIRE))) {
            do add_desire(predicate(SURVIVAL_DESIRE), 5.0);
            write "🚨 Helicóptero [" + name + "]: CRITICAL STRESS (" + int(stress_level) + "). Emergency landing.";
        }

        // Fuel critical
        if (fuel_level <= (aerial_firefighter_max_fuel * 0.2) and !has_desire(predicate(REFUEL_FUEL_DESIRE))) {
            operational_state <- "Repostando";
            do add_desire(predicate(REFUEL_FUEL_DESIRE), 5.0);
            write "⛽ Helicóptero [" + name + "]: FUEL CRITICAL (" + int(fuel_level) + "L). Returning to base.";
        }

        // Water critical
        if (water_load <= (aerial_firefighter_max_water * 0.15) and !has_desire(predicate(REFUEL_WATER_DESIRE))) {
            do add_desire(predicate(REFUEL_WATER_DESIRE), 4.0);
            write "💧 Helicóptero [" + name + "]: WATER LOW (" + int(water_load) + "L). Need to refill.";
        }
    }

    // --- COGNITIVE PLANS ---

    plan tactical_retreat intention: predicate(SURVIVAL_DESIRE) {
        operational_state <- "Repostando";
        logistics_base safe_zone <- logistics_base with_min_of (each distance_to self);

        if (safe_zone != nil) {
            do goto target: {safe_zone.location.x, safe_zone.location.y, safe_zone.location.z + 50.0} speed: speed;

            if ({location.x, location.y} distance_to {safe_zone.location.x, safe_zone.location.y} < 100.0) {
                stress_level <- 0.0;
                wind_exposure <- 0.0;
                operational_state <- "Disponible";
                do remove_desire(predicate(SURVIVAL_DESIRE));
                write "🚁 Helicóptero [" + name + "]: Safe at base. Status normalized.";
            }
        }
    }

    plan refuel_fuel intention: predicate(REFUEL_FUEL_DESIRE) {
        logistics_base target_base <- logistics_base with_min_of (each distance_to self);
        if (target_base != nil) {
            do goto target: {target_base.location.x, target_base.location.y, target_base.location.z + 50.0} speed: speed;

            if ({location.x, location.y} distance_to {target_base.location.x, target_base.location.y} < 100.0) {
                fuel_level <- aerial_firefighter_max_fuel;
                operational_state <- "Disponible";
                do remove_desire(predicate(REFUEL_FUEL_DESIRE));
                write "⛽ Helicóptero [" + name + "]: Fuel tank refilled. Ready for operations.";
            }
        }
    }

    plan refuel_water intention: predicate(REFUEL_WATER_DESIRE) {
        water_point nearest_water <- water_point with_min_of (each distance_to self);
        if (nearest_water != nil) {
            do goto target: {nearest_water.location.x, nearest_water.location.y, nearest_water.location.z + 50.0} speed: speed;

            if ({location.x, location.y} distance_to {nearest_water.location.x, nearest_water.location.y} < 80.0) {
                water_load <- aerial_firefighter_max_water;
                operational_state <- "Disponible";
                do remove_desire(predicate(REFUEL_WATER_DESIRE));
                write "💧 Helicóptero [" + name + "]: Water tank refilled from reservoir.";
            }
        }
    }

    plan extinguish_fire intention: predicate(EXTINGUISH_DESIRE) {
        if (assigned_target_location = nil) {
            do remove_desire(predicate(EXTINGUISH_DESIRE));
            operational_state <- "Disponible";
            return;
        }

        operational_state <- "En vuelo";
        float distance_to_target <- {location.x, location.y} distance_to assigned_target_location;
        float extinction_radius <- 120.0;

        // If still far from target, move closer
        if (distance_to_target > extinction_radius) {
            do goto target: {assigned_target_location.x, assigned_target_location.y, location.z} speed: speed;
        } else {
            // Close enough for aerial attack!
            operational_state <- "Extinguiendo";
            
            // Search for fires in extinction radius
            geometry extinction_zone <- circle(extinction_radius) at_location {location.x, location.y};
            list<terrain_cell> fires_to_extinguish <- (terrain_cell overlapping extinction_zone) where (each.is_burning);

            if (!empty(fires_to_extinguish)) {
                // Aerial drop: extinguish all fires (helicopters are efficient)
                int fires_count <- length(fires_to_extinguish);
                
                loop fire_cell over: fires_to_extinguish {
                    if (water_load > 30.0) {
                        float water_use <- 6.0 * (1.0 + (stress_level / aerial_firefighter_max_stress * 0.3));
                        water_load <- water_load - water_use;

                        fire_cell.is_burning <- false;
                        fire_cell.is_burned  <- true;
                        fire_cell.color      <- COLOR_BURNED;
                    }
                }
                write "💧 Helicóptero [" + name + "]: Aerial drop extinguished " + fires_count + " fires. Water: " + int(water_load) + "L";

                // Search for more fires or conclude
                geometry extended_search <- circle(250.0) at_location {location.x, location.y};
                list<terrain_cell> more_fires <- (terrain_cell overlapping extended_search) where (each.is_burning);

                if (!empty(more_fires)) {
                    assigned_target_location <- (more_fires with_min_of (each distance_to self)).location;
                    write "Helicóptero [" + name + "]: Relocating to next fire cluster.";
                } else {
                    write "Helicóptero [" + name + "]: Area secure, no active fires detected.";
                    assigned_target_location <- nil;
                    operational_state <- "Disponible";
                    do remove_desire(predicate(EXTINGUISH_DESIRE));
                }
            } else {
                // No fires in radius
                assigned_target_location <- nil;
                operational_state <- "Disponible";
                do remove_desire(predicate(EXTINGUISH_DESIRE));
            }
        }
    }

    reflex debug_helicopter when: assigned_target_location != nil and operational_state = "En vuelo" {
        float dist_to_target <- {location.x, location.y} distance_to assigned_target_location;
        write "[AERIAL] Helicóptero [" + name + "]: Distance to target = " + int(dist_to_target) + "m. Fuel: " + int(fuel_level) + "L, Water: " + int(water_load) + "L";
    }
}
