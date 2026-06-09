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
    // Registro de focos ya asignados (Protocolo 2 — evitación de redundancia)
    list<point> assigned_fires <- [];
    float assignment_radius <- 150.0; // metros — dos focos dentro de este radio se consideran el mismo
    // Base de creencias: estado conocido de cada foco (Protocolo 3)
	map<point, string> known_fire_states <- map([]);
    
    // --- VISUAL ASPECT ---
    aspect default {
        // Render a glowing yellow sphere above the base to represent the command center
        draw sphere(30.0) color: #yellow border: #orange;
    }

    // --- COGNITIVE ACTIONS ---

    // Entry point for Protocol 1 (Fire Notification)
    action receive_fire_alert(recon_drone sender, point fire_location, float fire_intensity, float fuel_available) {
        write "🔔 [Protocolo 1] Coordinador: Alerta recibida en " + fire_location;
        // Registrar el fuego como activo en la memoria global
        known_fire_states[fire_location] <- "activo"; 
        write "✓ [Protocolo 1] Confirm(focoDetectado) → Dron [" + sender.name + "]";
        do dispatch_optimal_unit(fire_location);
    }
    
    // Entry point for Protocol 6 (Battery Low Alert)
    action receive_battery_alert(recon_drone sender, string sector_id, float battery_percent) {
        write "🔋 [Protocolo 6] Coordinador: Dron [" + sender.name + "] batería baja (" + int(battery_percent) + "%). Buscando relevo para su sector...";
        // Buscar drones con más del 50% de batería
        list<recon_drone> available_drones <- recon_drone where (each != sender and each.battery_level > (drone_max_fuel * 0.5));
        
        if (!empty(available_drones)) {
            recon_drone relief <- available_drones with_min_of (each distance_to sender);
            write "📡 [Protocolo 6] Coordinador: Relevo de dron despachado a [" + relief.name + "]";
            
            ask relief {
                do receive_sector_delegation(sender.patrol_route);
            }
        } else {
            write "🚨 [Protocolo 6] Coordinador: Sin drones con batería suficiente para cubrir el sector de [" + sender.name + "]";
        }
    }

    // Protocolo 3: Recibir reportes de estado unificado
    action receive_status_update(agent sender, point fire_location, string fire_state, float progress, float water_level, float param_extra) {
	    known_fire_states[fire_location] <- fire_state;
	    
	    string resource_text <- "";
	    if (sender is bombero_terrestre) {
	        resource_text <- ", estrés=" + int(param_extra);
	    } else if (sender is bombero_aereo) {
	        resource_text <- ", fuel=" + int(param_extra) + "L";
	    }
	    
	    write "📊 [Protocolo 3] Coordinador: Inform(focoActualizado) de [" + sender.name
	        + "] — estado=" + fire_state
	        + ", progreso=" + int(progress) + "%"
	        + ", agua=" + int(water_level) + "L"
	        + resource_text;
	        
	    write "✓ [Protocolo 3] Confirm(focoActualizado(" + fire_location + ")) → [" + sender.name + "]";
	    
	    if (fire_state = "controlado" or fire_state = "extinguido") {
	        assigned_fires <- assigned_fires where (each distance_to fire_location >= assignment_radius);
	        write "🗺️ [Protocolo 3] Coordinador: Foco en " + fire_location + " liberado del registro de asignaciones.";
	    }
	}

    // Protocolo 4: Recibir petición de refuerzos
    action receive_reinforcement_request(agent sender, point target_location, float fire_count) {
        write "⚠️ [Protocolo 4] Coordinador: Solicitud de refuerzos de [" + sender.name + "] para foco en " + target_location;
 
        list<bombero_terrestre> available_ground <- bombero_terrestre where (each.operational_state = "Disponible" and each != sender);
        if (!empty(available_ground)) {
            bombero_terrestre reinforcement <- available_ground with_min_of (each distance_to target_location);
            write "📡 [Protocolo 4] Coordinador: Refuerzo terrestre a [" + reinforcement.name + "]";
            ask reinforcement {
                do request_mission(target_location);
            }
        } else {
            // Si no hay terrestres, buscar apoyo aéreo
            list<bombero_aereo> available_aerial <- bombero_aereo where (each.operational_state = "Disponible" and each != sender);
            
            if (!empty(available_aerial)) {
                bombero_aereo reinforcement <- available_aerial with_min_of (each distance_to target_location);
                write "🚁 [Protocolo 4] Coordinador: Refuerzo aéreo a [" + reinforcement.name + "]";
                ask reinforcement {
                    do request_mission(target_location);
                }
            } else {
                write "🚨 [Protocolo 4] Coordinador: Sin unidades disponibles (terrestres ni aéreas) para refuerzo";
            }
        }
    }
    
    // Protocolo 5 Unificado (Terrestre y Aéreo)
    action receive_withdrawal_notification(agent sender, point target_location, string reason) {
        if (target_location = nil) { return; } // Si se retiraba estando sin misión, ignorar
        
        write "💧 [Protocolo 5] Coordinador: [" + sender.name + "] se retira por " + reason + ". Buscando relevo para el foco en " + target_location;
        
        // Intentar buscar relevo terrestre cerca del foco
        list<bombero_terrestre> available_ground <- bombero_terrestre where (each.operational_state = "Disponible" and each != sender);
        
        if (!empty(available_ground)) {
            bombero_terrestre relief <- available_ground with_min_of (each distance_to target_location);
            write "📡 [Protocolo 5] Coordinador: Relevo terrestre despachado a [" + relief.name + "]";
            ask relief { do request_mission(target_location); }
            return;
        }
        
        // Si no hay terrestres, buscar relevo aéreo cerca del foco
        list<bombero_aereo> available_aerial <- bombero_aereo where (each.operational_state = "Disponible" and each != sender);
        
        if (!empty(available_aerial)) {
            bombero_aereo relief <- available_aerial with_min_of (each distance_to target_location);
            write "📡 [Protocolo 5] Coordinador: Relevo aéreo despachado a [" + relief.name + "]";
            ask relief { do request_mission(target_location); }
            return;
        }
        
        write "🚨 [Protocolo 5] Coordinador: Sin relevos operativos para cubrir la retirada en " + target_location;
    }
    
    // Protocolo 8 Unificado (Terrestre y Aéreo)
    action receive_emergency_evacuation(agent sender, point target_location, float stress_level) {
        write "🚨 [Protocolo 8] Coordinador: [" + sender.name + "] en emergencia (estrés: " + int(stress_level) + "). Enviando relevo...";
        
        if (target_location != nil) {
            if (sender is bombero_terrestre) {
                list<bombero_terrestre> available <- bombero_terrestre where (each.operational_state = "Disponible" and each != sender);
                if (!empty(available)) {
                    bombero_terrestre relief <- available with_min_of (each distance_to target_location);
                    write "📡 [Protocolo 8] Coordinador: Relevo terrestre a [" + relief.name + "] para foco " + target_location;
                    ask relief { do request_mission(target_location); }
                }
            } else if (sender is bombero_aereo) {
                list<bombero_aereo> available <- bombero_aereo where (each.operational_state = "Disponible" and each != sender);
                if (!empty(available)) {
                    bombero_aereo relief <- available with_min_of (each distance_to target_location);
                    write "📡 [Protocolo 8] Coordinador: Relevo aéreo a [" + relief.name + "] para foco " + target_location;
                    ask relief { do request_mission(target_location); }
                }
            }
        }
    }
    
    // Protocolo 9 Unificado con Reasignación Proactiva
    action receive_mission_completion(agent sender, point completed_location) {
        write "✅ [Protocolo 9] Coordinador: Misión completada por [" + sender.name + "] en " + completed_location;
        
        if (completed_location != nil) {
            // Liberar el foco del registro
            assigned_fires <- assigned_fires where (each distance_to completed_location >= assignment_radius);
            known_fire_states[completed_location] <- "extinguido";

            // Avisar a los drones para que limpien sus creencias (Sincronización global centralizada)
            ask recon_drone {
                do receive_mission_completion(completed_location);
            }
        }
        // Buscar el siguiente foco urgente no asignado en el Backlog
        write "🔍 [Protocolo 9] Coordinador: Buscando focos pendientes para reasignar a la unidad libre...";
        point pending_fire <- nil;
        
        loop loc over: known_fire_states.keys {
            if (known_fire_states[loc] = "activo") {
                bool is_assigned <- false;
                loop assigned_pt over: assigned_fires {
                    if (assigned_pt distance_to loc < assignment_radius) {
                        is_assigned <- true;
                        break;
                    }
                }
                if (!is_assigned) {
                    pending_fire <- loc;
                    break; // Foco huérfano encontrado
                }
            }
        }
        if (pending_fire != nil) {
            write "⚡ [Protocolo 9] Coordinador: Foco pendiente encontrado en " + pending_fire + ". Redirigiendo unidad.";
            do dispatch_optimal_unit(pending_fire);
        } else {
            write "☕ [Protocolo 9] Coordinador: No hay focos activos pendientes. Unidades en espera.";
        }
    }

    action receive_fuel_refuel_request(bombero_aereo aerial_unit, point target_location) {
        write "⛽ [Protocolo 7] Coordinador: [" + aerial_unit.name + "] solicita permiso para repostar combustible.";
        
        if (target_location != nil) {
            write "📡 [Protocolo 7] Coordinador: Buscando relevo para cubrir el foco en " + target_location;
            
            list<bombero_aereo> available <- bombero_aereo where (each.operational_state = "Disponible" and each != aerial_unit);
            
            if (!empty(available)) {
                bombero_aereo relief <- available with_min_of (each distance_to target_location);
                write "📡 [Protocolo 7] Coordinador: Relevo aéreo despachado a [" + relief.name + "]";
                ask relief { do request_mission(target_location); }
            } else {
                write "🚨 [Protocolo 7] Coordinador: Sin relevos aéreos operativos para cubrir el foco.";
            }
        }
    }

    // Protocol 2 (Mission Assignment) Logic
    action dispatch_optimal_unit(point target_location) {
	    // Comprobar si ya hay una unidad asignada a este foco o uno muy cercano
	    bool already_assigned <- false;
	    loop assigned_pt over: assigned_fires {
	        if (assigned_pt distance_to target_location < assignment_radius) {
	            already_assigned <- true;
	            break;
	        }
	    }
	    if (already_assigned) {
	        write "⚙️ [Protocolo 2] Coordinador: Foco en " + target_location + " ya tiene unidad asignada. Ignorando.";
	        return;
	    }
	
	    list<bombero_terrestre> available_ground <- bombero_terrestre where (each.operational_state = "Disponible");
	    list<bombero_aereo>     available_aerial <- bombero_aereo     where (each.operational_state = "Disponible");
	
	    bombero_terrestre best_ground <- empty(available_ground) ? nil : (available_ground with_min_of (each distance_to target_location));
	    bombero_aereo     best_aerial <- empty(available_aerial) ? nil : (available_aerial with_min_of (each distance_to target_location));
	
	    if (best_ground = nil and best_aerial = nil) {
            write "🚨 [Protocolo 2] Coordinador: Sin unidades disponibles (terrestres ni aéreas) para el foco en " + target_location;
            return;
        }

	    float eta_ground <- (best_ground != nil) ? (best_ground distance_to target_location) / firefighter_speed    : #max_float;
	    float eta_aerial <- (best_aerial != nil) ? (best_aerial distance_to target_location) / aerial_firefighter_speed : #max_float;
	
	    if (eta_ground <= eta_aerial * 1.5) {
	        // El terrestre llega en tiempo razonable, preferir terrestre (mayor capacidad de extinción)
	        write "📡 [Protocolo 2] Coordinador: REQUEST → [" + best_ground.name + "] para foco en " + target_location;
	        ask best_ground { do request_mission(target_location); }
	    } else {
	        // El aéreo llega significativamente antes, mandar aéreo
	        write "🚁 [Protocolo 2] Coordinador: REQUEST (ETA mejor) → [" + best_aerial.name + "] para foco en " + target_location;
	        ask best_aerial { do request_mission(target_location); }
	    }
	}
}
