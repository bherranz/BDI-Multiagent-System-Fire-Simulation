/**
* Name: Central Coordinator Agent
* Description: Strategic decision node for the centralized architecture.
* Memory compliance:
* - Evitación de redundancia y asignación óptima (§3.2.2)
* - Rango de cobertura y base de creencias (§3.4.1)
*/

model GredosCoordinador

import "parameters.gaml"
import "environment.gaml"
import "bombero_terrestre.gaml"
import "bombero_aereo.gaml"

species coordinador control: simple_bdi {
    // --- ATTRIBUTES ---
    float coverage_range <- 10000.0; // Communication range in meters
    
    // --- VISUAL ASPECT ---
    aspect default {
        // Render a glowing yellow sphere above the base to represent the command center
        draw sphere(30.0) color: #yellow border: #orange;
    }

    // --- COGNITIVE ACTIONS ---

    // Entry point for Protocol 1 (Fire Notification)
    action receive_fire_alert(point fire_location) {
        write "Coordinator: Alert received at coordinates " + fire_location + ". Calculating optimal dispatch...";
        do dispatch_optimal_unit(fire_location);
    }

    // Protocol 2 (Mission Assignment) Logic
    action dispatch_optimal_unit(point target_location) {
        // First, try to assign to ground firefighters
        list<bombero_terrestre> available_ground <- bombero_terrestre where (each.operational_state = "Disponible");

        if (!empty(available_ground)) {
            bombero_terrestre best_ground <- available_ground with_min_of (each distance_to target_location);
            write "📡 Coordinator: Sending REQUEST to Ground Unit [" + best_ground.name + "] for fire at " + target_location;
            
            ask best_ground {
                do request_mission(target_location);
            }
        } else {
            // No ground units available, try aerial units
            write "Coordinator: No ground units available. Attempting aerial dispatch...";
            
            list<bombero_aereo> available_aerial <- bombero_aereo where (each.operational_state = "Disponible");
            
            if (!empty(available_aerial)) {
                bombero_aereo best_aerial <- available_aerial with_min_of (each distance_to target_location);
                write "🚁 Coordinator: Sending REQUEST to Aerial Unit [" + best_aerial.name + "] for fire at " + target_location;
                
                ask best_aerial {
                    do request_mission(target_location);
                }
            } else {
                write "Coordinator: CRITICAL. No units available (ground or aerial) for dispatch at " + target_location;
            }
        }
    }
}
