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
import "recon_drone.gaml"
import "agente_operativo.gaml"

species coordinador control: simple_bdi {
    // --- ATTRIBUTES ---
    float coverage_range <- 10000.0; // Rango de comunicación en metros
    list<point> assigned_fires <- [];
    float assignment_radius <- 150.0; 
    map<point, string> known_fire_states <- map([]);
    // RNF-04: Verificar si el agente emisor está dentro del rango de cobertura
	bool en_rango(agent emisor) {
	    return (emisor distance_to self) <= coverage_range;
	}
    
    // --- VISUAL ASPECT ---
    aspect default {
        draw sphere(30.0) color: #yellow border: #orange;
    }
    
    reflex collect_intelligence when: every(20 #cycles) {
	    list<recon_drone> drones_in_range <- recon_drone where (each distance_to self < coverage_range);
	    list<point> new_fires <- [];
	
	    loop d over: drones_in_range {
	        ask d {
	            loop belief over: get_beliefs_with_name("wildfire_detected") {
	                point loc <- point(predicate(belief).values["location"]);
	                if (!(myself.known_fire_states.keys contains loc)) {
	                    new_fires <- new_fires + [loc];
	                }
	            }
	        }
	    }
	
	    loop loc over: new_fires {
	        write "[Protocolo 1 - Recuperado] Coordinador: Inteligencia remota en " + loc;
	        known_fire_states[loc] <- "activo";
	        do dispatch_optimal_unit(loc);
	    }
	}

    // --- COGNITIVE ACTIONS ---

    // Protocolo 1: Notificación de Incendio
    action receive_fire_alert(recon_drone sender, point fire_location, float fire_intensity, float fuel_available) {
        if (!en_rango(sender)) {
	        write "📵 [RNF-04] Coordinador: Mensaje de [" + sender.name + "] fuera de rango (" + int(sender distance_to self) + "m). Ignorado.";
	        return;
	    }
        write "[Protocolo 1] Coordinador: Alerta recibida en " + fire_location;
        known_fire_states[fire_location] <- "activo"; 
        write "[Protocolo 1] Confirm(focoDetectado) -> Dron [" + sender.name + "]";
        do dispatch_optimal_unit(fire_location);
    }

    // Protocolo 2 (Misión y Asignación): Despacho de la unidad óptima
    action dispatch_optimal_unit(point target_location) {
        bool already_assigned <- false;
        loop assigned_pt over: assigned_fires {
            if (assigned_pt distance_to target_location < assignment_radius) {
                already_assigned <- true;
                break;
            }
        }
        if (already_assigned) {
            write "[Protocolo 2] Coordinador: Foco en " + target_location + " ya tiene unidad asignada. Ignorando.";
            return;
        }
    
        list<bombero_terrestre> available_ground <- bombero_terrestre where (each.estado_operativo = "Disponible");
        list<bombero_aereo>     available_aerial <- bombero_aereo     where (each.estado_operativo = "Disponible");
    
        bombero_terrestre best_ground <- empty(available_ground) ? nil : (available_ground with_min_of (each distance_to target_location));
        bombero_aereo     best_aerial <- empty(available_aerial) ? nil : (available_aerial with_min_of (each distance_to target_location));
    
        if (best_ground = nil and best_aerial = nil) {
            write "[Protocolo 2] Coordinador: Sin unidades disponibles (terrestres ni aereas) para el foco en " + target_location;
            return;
        }

        float eta_ground <- (best_ground != nil) ? (best_ground distance_to target_location) / firefighter_speed    : #max_float;
        float eta_aerial <- (best_aerial != nil) ? (best_aerial distance_to target_location) / aerial_firefighter_speed : #max_float;
    
        if (eta_ground <= eta_aerial * 1.5) {
            write "[Protocolo 2] Coordinador: REQUEST -> [" + best_ground.name + "] para foco en " + target_location;
            ask best_ground { do request_mission(target_location); }
        } else {
            write "[Protocolo 2] Coordinador: REQUEST (ETA mejor) -> [" + best_aerial.name + "] para foco en " + target_location;
            ask best_aerial { do request_mission(target_location); }
        }
    }

    // Protocolo 3: Reporte de Estado
    action receive_status_update(agent sender, point target_location, string state, float progress, float res1, float res2) {
        if (!en_rango(sender)) {
	        write "📵 [RNF-04] Coordinador: Mensaje de [" + sender.name + "] fuera de rango (" + int(sender distance_to self) + "m). Ignorado.";
	        return;
	    }
        write "[Protocolo 3] Coordinador: Inform(focoActualizado) de [" + sender.name + "] - estado=" + state + ", progreso=" + int(progress) + "%";
        write "[Protocolo 3] Confirm(focoActualizado(" + target_location + ")) -> [" + sender.name + "]";
        known_fire_states[target_location] <- state;
        
        if (state = "controlado" or progress = 100.0) {
            assigned_fires <- assigned_fires where (each distance_to target_location >= assignment_radius);
            write "[Protocolo 3] Coordinador: Foco en " + target_location + " liberado del registro de asignaciones.";
        }
    }

    // Protocolo 4: Petición de refuerzos
    action receive_reinforcement_request(agent sender, point target_location, float fire_count) {
        if (!en_rango(sender)) {
	        write "📵 [RNF-04] Coordinador: Mensaje de [" + sender.name + "] fuera de rango (" + int(sender distance_to self) + "m). Ignorado.";
	        return;
	    }
        write "[Protocolo 4] Coordinador: Solicitud de refuerzos de [" + sender.name + "] para foco en " + target_location;
        
        list<bombero_terrestre> available_ground <- bombero_terrestre where (each.estado_operativo = "Disponible" and each != sender);
        
        if (!empty(available_ground)) {
            bombero_terrestre reinforcement <- available_ground with_min_of (each distance_to target_location);
            write "[Protocolo 4] Coordinador: Despachando refuerzo terrestre a [" + reinforcement.name + "]";
            ask reinforcement { do request_mission(target_location); }
        } else {
            list<bombero_aereo> available_aerial <- bombero_aereo where (each.estado_operativo = "Disponible" and each != sender);
            
            if (!empty(available_aerial)) {
                bombero_aereo reinforcement <- available_aerial with_min_of (each distance_to target_location);
                write "[Protocolo 4] Coordinador: Despachando refuerzo aereo a [" + reinforcement.name + "]";
                ask reinforcement { do request_mission(target_location); }
            } else {
                write "[Protocolo 4] Coordinador: Sin unidades disponibles (terrestres ni aereas) para refuerzo";
            }
        }
    }

    // Protocolo 5: Retirada por recarga de agua
    action receive_withdrawal_notification(agent sender, point target_location, string reason) {
        if (!en_rango(sender)) {
	        write "📵 [RNF-04] Coordinador: Mensaje de [" + sender.name + "] fuera de rango (" + int(sender distance_to self) + "m). Ignorado.";
	        return;
	    }
        if (target_location = nil) { return; } 
        
        write "[Protocolo 5] Coordinador: [" + sender.name + "] se retira por " + reason + ". Buscando relevo para el foco en " + target_location;
        
        list<bombero_terrestre> available_ground <- bombero_terrestre where (each.estado_operativo = "Disponible" and each != sender);
        
        if (!empty(available_ground)) {
            bombero_terrestre relief <- available_ground with_min_of (each distance_to target_location);
            write "[Protocolo 5] Coordinador: Relevo terrestre despachado a [" + relief.name + "]";
            ask relief { do request_mission(target_location); }
            return;
        }
        
        list<bombero_aereo> available_aerial <- bombero_aereo where (each.estado_operativo = "Disponible" and each != sender);
        
        if (!empty(available_aerial)) {
            bombero_aereo relief <- available_aerial with_min_of (each distance_to target_location);
            write "[Protocolo 5] Coordinador: Relevo aereo despachado a [" + relief.name + "]";
            ask relief { do request_mission(target_location); }
            return;
        }
        
        write "[Protocolo 5] Coordinador: Sin relevos operativos para cubrir la retirada en " + target_location;
    }

    // Protocolo 6: Gestión de batería (Dron)
    action receive_battery_alert(recon_drone sender, string sector_id, float battery_percent) {
        if (!en_rango(sender)) {
	        write "📵 [RNF-04] Coordinador: Mensaje de [" + sender.name + "] fuera de rango (" + int(sender distance_to self) + "m). Ignorado.";
	        return;
	    }
        write "[Protocolo 6] Coordinador: Dron [" + sender.name + "] bateria baja (" + int(battery_percent) + "%). Buscando relevo para su sector...";
        
        list<recon_drone> available_drones <- recon_drone where (each != sender and each.nivel_bateria > (drone_max_fuel * 0.5));
        
        if (!empty(available_drones)) {
            recon_drone relief <- available_drones with_min_of (each distance_to sender);
            write "[Protocolo 6] Coordinador: Relevo de dron despachado a [" + relief.name + "]";
            ask relief { do receive_sector_delegation(sender.patrol_route); }
        } else {
            write "[Protocolo 6] Coordinador: Sin drones con bateria suficiente para cubrir el sector de [" + sender.name + "]";
        }
    }

    // Protocolo 7: Repostaje de combustible (Aéreo)
    action receive_fuel_refuel_request(bombero_aereo aerial_unit, point target_location) {
        if (!en_rango(aerial_unit)) {
	        write "📵 [RNF-04] Coordinador: Mensaje de [" + aerial_unit.name + "] fuera de rango (" + int(aerial_unit distance_to self) + "m). Ignorado.";
	        return;
	    }
        write "[Protocolo 7] Coordinador: [" + aerial_unit.name + "] solicita permiso para repostar combustible.";
        
        if (target_location != nil) {
            write "[Protocolo 7] Coordinador: Buscando relevo para cubrir el foco en " + target_location;
            
            list<bombero_aereo> available <- bombero_aereo where (each.estado_operativo = "Disponible" and each != aerial_unit);
            
            if (!empty(available)) {
                bombero_aereo relief <- available with_min_of (each distance_to target_location);
                write "[Protocolo 7] Coordinador: Relevo aereo despachado a [" + relief.name + "]";
                ask relief { do request_mission(target_location); }
            } else {
                write "[Protocolo 7] Coordinador: Sin relevos aereos operativos para cubrir el foco.";
            }
        }
    }

    // Protocolo 8: Evacuación de emergencia
    action receive_emergency_evacuation(agent sender, point target_location, float stress_level) {
        if (!en_rango(sender)) {
	        write "📵 [RNF-04] Coordinador: Mensaje de [" + sender.name + "] fuera de rango (" + int(sender distance_to self) + "m). Ignorado.";
	        return;
	    }
        write "[Protocolo 8] Coordinador: [" + sender.name + "] en emergencia (estres: " + int(stress_level) + "). Enviando relevo...";
        
        if (target_location != nil) {
            if (sender is bombero_terrestre) {
                list<bombero_terrestre> available <- bombero_terrestre where (each.estado_operativo = "Disponible" and each != sender);
                if (!empty(available)) {
                    bombero_terrestre relief <- available with_min_of (each distance_to target_location);
                    write "[Protocolo 8] Coordinador: Relevo terrestre a [" + relief.name + "] para foco " + target_location;
                    ask relief { do request_mission(target_location); }
                }
            } else if (sender is bombero_aereo) {
                list<bombero_aereo> available <- bombero_aereo where (each.estado_operativo = "Disponible" and each != sender);
                if (!empty(available)) {
                    bombero_aereo relief <- available with_min_of (each distance_to target_location);
                    write "[Protocolo 8] Coordinador: Relevo aereo a [" + relief.name + "] para foco " + target_location;
                    ask relief { do request_mission(target_location); }
                }
            }
        }
    }

    // Protocolo 9: Finalización de Misión y Cierre de Foco
    action receive_mission_completion(agent sender, point completed_location) {
        if (!en_rango(sender)) {
	        write "📵 [RNF-04] Coordinador: Mensaje de [" + sender.name + "] fuera de rango (" + int(sender distance_to self) + "m). Ignorado.";
	        return;
	    }
        write "[Protocolo 9] Coordinador: Mision completada por [" + sender.name + "].";

        if (completed_location != nil) {
            assigned_fires <- assigned_fires where (each distance_to completed_location >= assignment_radius);
            known_fire_states[completed_location] <- "extinguido";
            
            ask recon_drone {
                do receive_mission_completion(completed_location);
            }
        }

        // Búsqueda Proactiva
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
                    break; 
                }
            }
        }
        
        if (pending_fire != nil) {
            write "[Protocolo 9] Coordinador: Reasignando foco pendiente en " + pending_fire;
            do dispatch_optimal_unit(pending_fire);
        } else {
            write "[Protocolo 9] Coordinador: No hay mas focos pendientes.";
        }
    }
}
