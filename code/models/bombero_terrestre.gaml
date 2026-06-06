/**
* Name: Ground Firefighter Agent (Bombero Terrestre)
* Description: BDI cognitive definition for the ground operative unit.
*/

model GredosBomberoTerrestre

import "parameters.gaml"
import "environment.gaml"
import "infrastructure.gaml"
import "main.gaml"

species bombero_terrestre control: simple_bdi skills: [moving] {

    // --- ONTOLOGICAL ATTRIBUTES ---
    float water_load        <- firefighter_max_water;
    float stress_level      <- 0.0;
    float fatigue_level     <- 0.0;
    string operational_state <- "Disponible"; // Disponible | Extinguiendo | Recargando | Retirada

    // Target assigned by Coordinator (Protocol 2)
    point assigned_target_location <- nil;

    // --- BDI PREDICATES ---
    string EXTINGUISH_DESIRE <- "extinguish_fire";
    string RECHARGE_DESIRE   <- "recharge_water";
    string REST_DESIRE       <- "rest_recover";
    string SURVIVAL_DESIRE   <- "self_protection";

    // --- VISUAL ASPECT ---
    aspect default {
        draw box(80.0, 100.0, 60.0) color: #red border: #white;
    }

    // --- INITIALISATION ---
    init {
        speed <- firefighter_speed;
        water_load <- firefighter_max_water; 
    }

    // --- COGNITIVE ACTIONS ---

    // Protocol 2: Evaluate and respond to mission request from Coordinator
    action request_mission(point target_location) {
        // Evaluate BDI state: water, stress, fatigue
        float stress_margin <- firefighter_max_stress - stress_level;
        float water_margin <- water_load - (firefighter_max_water * 0.15);
        float fatigue_margin <- firefighter_max_fatigue - fatigue_level;

        bool can_accept <- (water_margin > 0 and stress_margin > 10.0 and fatigue_margin > 10.0);

        if (can_accept) {
            write "🟢 Bombero [" + name + "]: AGREE — Accepting mission at " + target_location;
            assigned_target_location <- target_location;
            do add_desire(predicate(EXTINGUISH_DESIRE), 4.0);
        } else {
            write "🔴 Bombero [" + name + "]: REFUSE — Cannot accept mission (water: " + water_load + ", stress: " + stress_level + ", fatigue: " + fatigue_level + ")";
        }
    }

    // --- REFLEXES ---
    reflex adjust_altitude_to_terrain {
        terrain_cell current_cell <- terrain_cell(location);
        if (current_cell != nil) {
            location <- {location.x, location.y, current_cell.altitude + 20.0};
            if (current_cell.has_road) {
                speed <- firefighter_speed * 2.0;
            } else {
                terrain_cell steepest_nb <- current_cell.neighbors with_min_of (each.altitude);
                float slope_delta <- (steepest_nb != nil)
                    ? (current_cell.altitude - steepest_nb.altitude) * slope_influence_factor
                    : 0.0;
                speed <- max(3.0, (firefighter_speed * 0.6) - slope_delta * 50.0);
            }
        }
    }

    reflex debug_movement when: assigned_target_location != nil and operational_state = "Extinguiendo" {
        float dist_to_target <- {location.x, location.y} distance_to assigned_target_location;
    }

    reflex evaluate_emotions {
        if (operational_state = "Extinguiendo") {
            fatigue_level <- fatigue_level + 0.2;
            stress_level <- stress_level + 0.2;     // Add stress during active firefighting
        } else if (operational_state = "Disponible" and fatigue_level > 0) {
            fatigue_level <- fatigue_level - 0.15;
        }

        geometry safety_zone <- circle(100.0) at_location {location.x, location.y};
        list<terrain_cell> nearby_fire <- (terrain_cell overlapping safety_zone) where (each.is_burning);

        if (!empty(nearby_fire)) {
            stress_level <- stress_level + (length(nearby_fire) * 0.3);  // INCREASED from 0.1
        } else {
            stress_level <- max(0.0, stress_level - 0.5);
        }

        if (stress_level > firefighter_max_stress and !has_desire(predicate(SURVIVAL_DESIRE))) {
            operational_state <- "Retirada";
            do add_desire(predicate(SURVIVAL_DESIRE), 5.0);
            write "🚨 Bombero [" + name + "]: CRITICAL STRESS (" + int(stress_level) + "). Initiating tactical retreat.";
        }

        if (fatigue_level > firefighter_max_fatigue and !has_desire(predicate(REST_DESIRE))) {
            do add_desire(predicate(REST_DESIRE), 3.0);
            write "😴 Bombero [" + name + "]: EXHAUSTED (" + int(fatigue_level) + "). Requesting rest.";
        }

        if (water_load <= 0 and !has_desire(predicate(RECHARGE_DESIRE))) {
            operational_state <- "Recargando";
            do add_desire(predicate(RECHARGE_DESIRE), 4.0);
            write "💧 Bombero [" + name + "]: Out of water. Heading to recharge.";
        }
    }

    reflex avoid_fire_during_movement when: operational_state = "Extinguiendo" {
        terrain_cell current_cell <- terrain_cell(location);
        
        // If currently on fire, MUST leave immediately
        if (current_cell != nil and current_cell.is_burning) {
            write "⚠️ ALERT Bombero [" + name + "]: ON FIRE! Evacuating!";
            stress_level <- min(firefighter_max_stress, stress_level + 5.0); // Big stress spike
            
            // Move away from fire
            geometry safe_zone <- circle(50.0) at_location {location.x, location.y};
            list<terrain_cell> safe_cells <- (terrain_cell overlapping safe_zone) where (!each.is_burning);
            
            if (!empty(safe_cells)) {
                point safe_location <- (safe_cells with_max_of (each distance_to current_cell)).location;
                location <- {safe_location.x, safe_location.y, location.z};
            }
            return;
        }
    }

    reflex opportunistic_extinguish when: water_load > 0 {
        terrain_cell current_cell <- terrain_cell(location);
        if (current_cell != nil and current_cell.is_burning) {
            current_cell.is_burning <- false;
            current_cell.is_burned <- true;
            current_cell.color <- COLOR_BURNED;
            water_load <- water_load - 5.0;
            write "💧 Bombero [" + name + "]: Foco eliminado por el camino.";
        }
    }

    // ---ALGORITMO HÍBRIDO DE NAVEGACIÓN ---
    action move_hybrid(point target_pos) {
        // Si estamos muy cerca del objetivo, ir directamente sin usar el grafo
        float distance_to_target <- {location.x, location.y} distance_to target_pos;
        
        if (distance_to_target < 150.0) {
            // Última milla: ir a pie directo al foco
            do goto target: {target_pos.x, target_pos.y, location.z} speed: speed;
        } else {
            // Primera parte: navegar por carreteras
            // Encuentra el nodo del grafo más cercano al objetivo
            geometry closest_node_to_target <- road_network.vertices closest_to target_pos;
            
            if (closest_node_to_target != nil) {
                point node_location <- closest_node_to_target.location;
                float distance_to_node <- {location.x, location.y} distance_to {node_location.x, node_location.y};
                
                // Solo usar el grafo si el nodo está a más de 30m y nos acerca al objetivo
                if (distance_to_node > 30.0 and {node_location.x, node_location.y} distance_to target_pos < distance_to_target) {
                    // Navega usando la red vial hacia el nodo más cercano del objetivo
                    do goto target: {node_location.x, node_location.y, location.z} on: road_network speed: speed;
                } else {
                    // Si el nodo no ayuda, ir directo
                    do goto target: {target_pos.x, target_pos.y, location.z} speed: speed;
                }
            } else {
                // Si no hay nodo en el grafo, ir directo
                do goto target: {target_pos.x, target_pos.y, location.z} speed: speed;
            }
        }
    }

    // --- COGNITIVE PLANS ---

    plan tactical_retreat intention: predicate(SURVIVAL_DESIRE) {
        operational_state <- "Retirada";
        logistics_base safe_zone <- logistics_base with_min_of (each distance_to self);

        do move_hybrid(safe_zone.location);

        if ({location.x, location.y} distance_to {safe_zone.location.x, safe_zone.location.y} < 50.0) {
            stress_level     <- 0.0;
            operational_state <- "Disponible";
            do remove_desire(predicate(SURVIVAL_DESIRE));
            write "Bombero [" + name + "]: Reached safe zone. Stress normalised.";
        }
    }

    plan recharge_water intention: predicate(RECHARGE_DESIRE) {
        water_point nearest_water <- water_point with_min_of (each distance_to self);
        if (nearest_water != nil) {
            do move_hybrid(nearest_water.location);

            if ({location.x, location.y} distance_to {nearest_water.location.x, nearest_water.location.y} < 30.0) {
                water_load        <- firefighter_max_water;
                operational_state <- "Disponible";
                do remove_desire(predicate(RECHARGE_DESIRE));
                write "Bombero [" + name + "]: Tank refilled.";
            }
        }
    }

    plan rest_recover intention: predicate(REST_DESIRE) {
        operational_state <- "Disponible";
        fatigue_level     <- fatigue_level - 1.0;

        if (fatigue_level <= 0.0) {
            fatigue_level <- 0.0;
            do remove_desire(predicate(REST_DESIRE));
            write "Bombero [" + name + "]: Fatigue recovered. Ready.";
        }
    }

    plan extinguish_fire intention: predicate(EXTINGUISH_DESIRE) {
        if (assigned_target_location = nil) {
            do remove_desire(predicate(EXTINGUISH_DESIRE));
            operational_state <- "Disponible";
            return;
        }

        operational_state <- "Extinguiendo";
        float distance_to_target <- {location.x, location.y} distance_to assigned_target_location;
        
        // Define extinction radius (area around firefighter where they can extinguish)
        float extinction_radius <- 100.0;

        // If still far from target, move closer
        if (distance_to_target > extinction_radius) {
            do move_toward_target_safely;
        } else {
            // Close enough! Search for fires in extinction radius and extinguish them
            geometry extinction_zone <- circle(extinction_radius) at_location {location.x, location.y};
            list<terrain_cell> fires_to_extinguish <- (terrain_cell overlapping extinction_zone) where (each.is_burning);

            if (!empty(fires_to_extinguish)) {
                // Extinguish ALL fires in the zone - AGGRESSIVE extinction
                loop fire_cell over: fires_to_extinguish {
                    if (water_load > 50.0) {
                        // Use less water per cell but hit ALL of them
                        float water_use <- 8.0 * (1.0 + (stress_level / firefighter_max_stress * 0.5));
                        water_load <- water_load - water_use;

                        fire_cell.is_burning <- false;
                        fire_cell.is_burned  <- true;
                        fire_cell.color      <- COLOR_BURNED;
                    }
                }
                write "💧 Bombero [" + name + "]: Extinguished " + length(fires_to_extinguish) + " fires. Water: " + int(water_load) + "L";

                // After extinguishing, search for more nearby fires
                geometry extended_search <- circle(250.0) at_location {location.x, location.y};
                list<terrain_cell> more_fires <- (terrain_cell overlapping extended_search) where (each.is_burning);

                if (!empty(more_fires)) {
                    // Move to the next fire
                    assigned_target_location <- (more_fires with_min_of (each distance_to self)).location;
                    write "Bombero [" + name + "]: Moving to next fire cluster at " + assigned_target_location;
                } else {
                    // No more fires, mission complete
                    write "Bombero [" + name + "]: Sector secured, no active fires.";
                    assigned_target_location <- nil;
                    operational_state <- "Disponible";
                    do remove_desire(predicate(EXTINGUISH_DESIRE));
                }
            } else {
                // Target area already burned or no fire nearby
                assigned_target_location <- nil;
                operational_state <- "Disponible";
                do remove_desire(predicate(EXTINGUISH_DESIRE));
            }
        }
    }

    // Helper action to move safely (don't traverse burning cells)
    action move_toward_target_safely {
        terrain_cell current_cell <- terrain_cell(location);
        
        // Check if standing on fire
        if (current_cell != nil and current_cell.is_burning) {
            write "⚠️ Bombero [" + name + "]: Standing on fire! Must move!";
            stress_level <- min(firefighter_max_stress, stress_level + 3.0);
            
            // Move away from fire - find nearest safe cell
            geometry escape_zone <- circle(50.0) at_location {location.x, location.y};
            list<terrain_cell> safe_cells <- (terrain_cell overlapping escape_zone) where (!each.is_burning);
            
            if (!empty(safe_cells)) {
                point safe_location <- (safe_cells with_max_of (each distance_to current_cell)).location;
                location <- {safe_location.x, safe_location.y, location.z};
            }
            return;
        }
        
        // Normal movement toward target
        point direction <- assigned_target_location - {location.x, location.y};
        float norm <- sqrt(direction.x ^ 2 + direction.y ^ 2);
        
        if (norm > 0) {
            point normalized_direction <- {direction.x / norm, direction.y / norm};
            point next_location <- {location.x + (normalized_direction.x * speed), 
                                   location.y + (normalized_direction.y * speed), 
                                   location.z};
            
            // Check if next position is on fire - if so, find an alternate path
            terrain_cell next_cell <- terrain_cell(next_location);
            if (next_cell != nil and next_cell.is_burning) {
                // Path blocked by fire - try to go around it
                write "🔥 Bombero [" + name + "]: Fire detected ahead, finding alternate route.";
                stress_level <- min(firefighter_max_stress, stress_level + 1.0);
                
                // Find 3 alternate paths and pick the safest
                float angle_offset <- 45.0; // Try +/- 45 degrees
                bool found_path <- false;
                
                loop offset over: [-angle_offset, angle_offset] {
                    float new_angle <- (normalized_direction direction_to {0,0}) + offset;
                    point alt_direction <- {cos(new_angle), sin(new_angle)};
                    point alt_location <- {location.x + (alt_direction.x * speed),
                                         location.y + (alt_direction.y * speed),
                                         location.z};
                    
                    terrain_cell alt_cell <- terrain_cell(alt_location);
                    if (alt_cell = nil or !alt_cell.is_burning) {
                        location <- alt_location;
                        found_path <- true;
                        break;
                    }
                }
                
                // If no alternate path, just skip this cycle
                if (!found_path) {
                    write "⚠️ Bombero [" + name + "]: Surrounded by fire, waiting for clearance.";
                }
                return;
            }
            
            // Safe to move
            location <- next_location;
        }
    }
}
