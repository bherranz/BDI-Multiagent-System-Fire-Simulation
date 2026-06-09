/**
* Name: Ground Firefighter Agent (Bombero Terrestre)
* Description: BDI cognitive definition for the ground operative unit.
*/

model GredosBomberoTerrestre

import "parameters.gaml"
import "recon_drone.gaml"
import "environment.gaml"
import "infrastructure.gaml"
import "main.gaml"

species bombero_terrestre control: simple_bdi skills: [moving] {

    // --- ONTOLOGICAL ATTRIBUTES ---
    float water_load        <- firefighter_max_water;
    float stress_level      <- 0.0;
    float fatigue_level     <- 0.0;
    string operational_state <- "Disponible"; // Disponible | Extinguiendo | Recargando | Retirada
    float last_reported_progress <- -1.0;

    // Target assigned by Coordinator (Protocol 2)
    point assigned_target_location <- nil;
    // Referencia para calcular progreso real (Protocolo 3)
	int initial_fire_count <- 0;
	// Mapa local de creencias sobre focos (Protocolo 3 - Modelo Descentralizado)
	map<point, string> known_fires_local <- map([]);
	bool reinforcement_requested <- false; // Evita spam del Protocolo 4
	bool withdrawal_notified <- false;     // Evita el spam del Protocolo 5
	bool emergency_notified <- false;

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

    // Protocolo 2: Evaluación de misión y negociación BDI
    action request_mission(point target_location) {
        // Evaluate BDI state: water, stress, fatigue
        float stress_margin <- firefighter_max_stress - stress_level;
        float water_margin <- water_load - (firefighter_max_water * 0.15);
        float fatigue_margin <- firefighter_max_fatigue - fatigue_level;

        bool can_accept <- (water_margin > 0 and stress_margin > 10.0 and fatigue_margin > 10.0);

        if (can_accept) {
		    write "🟢 [Protocolo 2] Bombero [" + name + "]: AGREE — Aceptando misión en " + target_location;
		    assigned_target_location <- target_location;
		    geometry initial_zone <- circle(150.0) at_location target_location;
		    initial_fire_count <- length((terrain_cell overlapping initial_zone) where (each.is_burning));
		    do add_desire(predicate(EXTINGUISH_DESIRE), 4.0);
		    reinforcement_requested <- false;
		    // Registrar el foco como asignado solo si el agente acepta
		    ask one_of(coordinador) {
		        list<point> coincidentes <- assigned_fires where (each distance_to target_location < assignment_radius);
		        if (empty(coincidentes)) {
		            assigned_fires <- assigned_fires + [target_location];
		        }
		    }
		    // Registrar belief focoAsignado para evitar redundancia en modelo descentralizado
			if (!is_centralized_model) {
			    do add_belief(predicate("foco_asignado", ["location"::target_location]));
			}
		} else {
            write "🔴 [Protocolo 2] Bombero [" + name + "]: REFUSE — No puede aceptar (agua: " + int(water_load) + "L, estrés: " + int(stress_level) + ", fatiga: " + int(fatigue_level) + ")";
        }
    }
    
    // Protocolo 2 CNP: calcular y devolver coste estimado para una puja
	action calculate_bid(point target_location) type: float {
	    // Coste base = distancia al foco
	    float distance_cost <- location distance_to target_location;
	    // Penalización por recursos bajos (menos agua = peor candidato)
	    float water_penalty <- (1.0 - (water_load / firefighter_max_water)) * 5000.0;
	    // Penalización por estrés y fatiga acumulados
	    float condition_penalty <- (stress_level + fatigue_level) * 50.0;
	    // Unidades no disponibles no pujan (coste infinito)
	    if (operational_state != "Disponible") {
	        return #max_float;
	    }
	    return distance_cost + water_penalty + condition_penalty;
	}
    
    // Protocolo 3: Informe de estado y progreso periódico
    action report_status_to_coordinator {
	    geometry mission_zone <- circle(150.0) at_location assigned_target_location;
        list<terrain_cell> nearby_fires <- (terrain_cell overlapping mission_zone) where (each.is_burning);
        
        string fire_state <- empty(nearby_fires) ? "controlado" : "activo";
        int current_fire_count <- length(nearby_fires);

        float progress <- (initial_fire_count > 0)
            ? max(0.0, min(100.0, (1.0 - (float(current_fire_count) / float(initial_fire_count))) * 100.0))
            : 100.0;
            
        if (abs(progress - last_reported_progress) >= 5.0 or progress = 100.0) {
            last_reported_progress <- progress;
            
            write "📊 [Protocolo 3] Bombero [" + name + "]: Inform(focoActualizado(estado=" + fire_state
                + ", progreso=" + int(progress) + "%, agua=" + int(water_load) + "L, estrés=" + int(stress_level) + "))";
                
            if (is_centralized_model) {
                ask one_of(coordinador) {
                    do receive_status_update(myself, myself.assigned_target_location, fire_state, progress, myself.water_load, myself.stress_level);
                }
            } else {
                float broadcast_range <- 500.0;
                list<bombero_terrestre> nearby_peers <- bombero_terrestre where (each != self and each distance_to self < broadcast_range);
                ask nearby_peers {
                    do receive_status_broadcast(myself.assigned_target_location, fire_state, progress);
                }
            }
        }
    }    
	
	// Protocolo 3 P2P: recibir actualización de estado de un par
	action receive_status_broadcast(point fire_location, string fire_state, float progress) {
	    known_fires_local[fire_location] <- fire_state;
	    write "📡 [Protocolo 3 - P2P] Bombero [" + name + "]: Sincroniza foco "
	        + fire_location + " → " + fire_state + " (" + int(progress) + "%)";
	}

    // Protocolo 4: Petición de refuerzos cuando propagación > capacidad
    action request_reinforcements {
        if (reinforcement_requested) { return; }

        geometry search_zone <- circle(200.0) at_location {location.x, location.y};
        list<terrain_cell> nearby_fires <- (terrain_cell overlapping search_zone) where (each.is_burning);
        float fire_count <- float(length(nearby_fires));

        if (fire_count > 5.0 and water_load < firefighter_max_water * 0.5) {
            write "⚠️ [Protocolo 4] Bombero [" + name + "]: Request(ayudar(foco=" + assigned_target_location + "))";
            
            if (is_centralized_model) {
                ask one_of(coordinador) {
                    // Pasamos el foco al que ir, no la ubicación actual del bombero
                    do receive_reinforcement_request(myself, myself.assigned_target_location, fire_count);
                }
            } else {
                // Modelo descentralizado: Pide ayuda a compañeros y helicópteros cercanos
                float broadcast_range <- 500.0;
                list<bombero_terrestre> nearby_ground <- bombero_terrestre where (each != self and each distance_to self < broadcast_range);
                list<bombero_aereo> nearby_aerial <- bombero_aereo where (each distance_to self < broadcast_range);
                
                ask nearby_ground { do request_mission(myself.assigned_target_location); }
                ask nearby_aerial { do request_mission(myself.assigned_target_location); }
            }
            reinforcement_requested <- true; // Marcamos que la ayuda ya está pedida
        }
    }
    
    // Protocolo 5: Notificación de retirada para recargar agua
    action notify_water_withdrawal {
        if (assigned_target_location != nil) {
            write "💧 [Protocolo 5] Bombero [" + name + "]: Inform(retiradaRecarga(foco=" + assigned_target_location + "))";
            
            if (is_centralized_model) {
                ask one_of(coordinador) {
                    do receive_withdrawal_notification(myself, myself.assigned_target_location, "water_refill");
                }
            } else {
                // Modelo descentralizado: Broadcast a todos los pares (Bomberos y Drones)
                float broadcast_range <- 600.0;
                list<bombero_terrestre> nearby_ground <- bombero_terrestre where (each != self and each distance_to self < broadcast_range);
                list<bombero_aereo> nearby_aerial <- bombero_aereo where (each distance_to self < broadcast_range);
                list<recon_drone> nearby_drones <- recon_drone where (each distance_to self < broadcast_range);
                ask nearby_drones {
                    write "📡 [Protocolo 5 - P2P] Dron [" + name + "]: Recibe aviso de retirada. Reevaluando sector " + myself.assigned_target_location;
                    if (!(myself.assigned_target_location in patrol_route)) {
                        patrol_route <- [myself.assigned_target_location] + patrol_route;
                    }
                }
                // Verificar si el foco sigue activo antes de enviar relevo (evita misiones a focos extinguidos)
				geometry target_zone <- circle(150.0) at_location assigned_target_location;
				bool fire_still_active <- !empty((terrain_cell overlapping target_zone) where (each.is_burning));
				
				if (fire_still_active) {
				    ask nearby_ground { do request_mission(myself.assigned_target_location); }
				    ask nearby_aerial { do request_mission(myself.assigned_target_location); }
				} else {
				    write "ℹ️ [Protocolo 5 - P2P] Foco en " + assigned_target_location + " ya extinguido. No se envía relevo.";
				}
            }
        }
    }
    
    // Protocolo 8: Evacuación de emergencia por seguridad crítica
    action emergency_evacuation_protocol {
        write "🚨 [Protocolo 8] Bombero [" + name + "]: Inform(retiradaEmergencia(riesgo_crítico))";
        operational_state <- "Retirada";
        
        if (assigned_target_location != nil) {
            if (is_centralized_model) {
                ask one_of(coordinador) {
                    do receive_emergency_evacuation(myself, myself.assigned_target_location, myself.stress_level);
                }
            } else {
                // Modelo descentralizado: Broadcast de emergencia a pares
                float broadcast_range <- 600.0;
                list<bombero_terrestre> nearby_ground <- bombero_terrestre where (each != self and each distance_to self < broadcast_range);
                list<bombero_aereo> nearby_aerial <- bombero_aereo where (each distance_to self < broadcast_range);
                list<recon_drone> nearby_drones <- recon_drone where (each distance_to self < broadcast_range);
                
                ask nearby_drones {
                    if (!(myself.assigned_target_location in patrol_route)) {
                        patrol_route <- [myself.assigned_target_location] + patrol_route;
                    }
                }
                ask nearby_ground { do request_mission(myself.assigned_target_location); }
                ask nearby_aerial { do request_mission(myself.assigned_target_location); }
            }
        }
    }
    
    // Protocolo 9: Notificación de misión completada
    action notify_mission_completion {
        point finished_target <- assigned_target_location;
        write "✅ [Protocolo 9] Bombero [" + name + "]: Inform(misionCompletada(foco=" + finished_target + "))";
        
        if (is_centralized_model) {
            ask one_of(coordinador) {
                // Pasamos la ubicación exacta del foco apagado
                do receive_mission_completion(myself, finished_target);
            }
        } else {
            // Modelo descentralizado: Broadcast para que los drones limpien sus creencias
            float broadcast_range <- 1500.0; 
            list<recon_drone> nearby_drones <- recon_drone where (each distance_to self < broadcast_range);
            ask nearby_drones {
                do receive_mission_completion(finished_target);
            }
            do remove_belief(predicate("foco_asignado", ["location"::finished_target]));
        }
        // Limpieza del estado del agente
        assigned_target_location <- nil;
        operational_state <- "Disponible";
        reinforcement_requested <- false;
        withdrawal_notified <- false;
        last_reported_progress <- -1.0;
        
        do remove_desire(predicate(EXTINGUISH_DESIRE));
    }

    // --- REFLEXES ---
    
    // Protocolo 3: Reportes periódicos de estado
    reflex protocol_3_periodic_status when: operational_state = "Extinguiendo" and every(15 #cycles) {
        do report_status_to_coordinator;
    }
    
    // Protocolo 4: Detectar necesidad de refuerzos
    reflex protocol_4_check_reinforcements when: operational_state = "Extinguiendo" and (int(cycle) mod 7 = 0) {
        do request_reinforcements;
    }
    
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

        if (water_load <= (firefighter_max_water * 0.15) and !has_desire(predicate(RECHARGE_DESIRE))) {
            operational_state <- "Recargando";
            do remove_desire(predicate(EXTINGUISH_DESIRE)); // Soltamos el fuego
            do add_desire(predicate(RECHARGE_DESIRE), 5.0); // Prioridad máxima
            write "💧 Bombero [" + name + "]: Agua crítica (" + int(water_load) + "L). Heading to recharge.";
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
        // Ejecutar notificación solo 1 vez
        if (!emergency_notified) {
            do emergency_evacuation_protocol;
            assigned_target_location <- nil;
            emergency_notified <- true;
        }

        logistics_base safe_zone <- logistics_base with_min_of (each distance_to self);
        do move_hybrid(safe_zone.location);

        if ({location.x, location.y} distance_to {safe_zone.location.x, safe_zone.location.y} < 50.0) {
            stress_level <- 0.0;
            operational_state <- "Disponible";
            emergency_notified <- false; // Reseteamos el semáforo
            do remove_desire(predicate(SURVIVAL_DESIRE));
            write "Bombero [" + name + "]: Reached safe zone. Stress normalised.";
        }
    }

	plan recharge_water intention: predicate(RECHARGE_DESIRE) {
        // Protocolo 5: Notificar retirada para recarga
        if (!withdrawal_notified) {
            do notify_water_withdrawal;
            withdrawal_notified <- true;
        }
        
        water_point nearest_water <- water_point with_min_of (each distance_to self);
        if (nearest_water != nil) {
            do move_hybrid(nearest_water.location);
            
            if ({location.x, location.y} distance_to {nearest_water.location.x, nearest_water.location.y} < 30.0) {
                water_load <- firefighter_max_water;
                operational_state <- "Disponible";
                withdrawal_notified <- false;
                assigned_target_location <- nil;
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
                // Apagar agresivamente los fuegos en el radio corto
                loop fire_cell over: fires_to_extinguish {
                    // Calcular el agua antes de intentar apagar
                    float water_use <- 8.0 * (1.0 + (stress_level / firefighter_max_stress * 0.5));
                    if (water_load >= water_use) {
                        water_load <- water_load - water_use;
                        fire_cell.is_burning <- false;
                        fire_cell.is_burned  <- true;
                        fire_cell.color      <- COLOR_BURNED;
                    }
                }
                write "💧 Bombero [" + name + "]: Apagando. Agua: " + int(water_load) + "L";
            } else {
                // Solo hacemos el escaneo de 250m cuando el área inmediata está limpia
                geometry extended_search <- circle(250.0) at_location {location.x, location.y};
                list<terrain_cell> more_fires <- (terrain_cell overlapping extended_search) where (each.is_burning);

                if (!empty(more_fires)) {
                    assigned_target_location <- (more_fires with_min_of (each distance_to self)).location;
                    // Resetear referencia de progreso para el nuevo foco
                    geometry new_zone <- circle(150.0) at_location assigned_target_location;
                    initial_fire_count <- length((terrain_cell overlapping new_zone) where (each.is_burning));
                    write "Bombero [" + name + "]: Moviéndose al siguiente grupo de fuego en " + assigned_target_location;
                } else {
                    write "Bombero [" + name + "]: Sector asegurado, no hay fuegos activos.";
                    do notify_mission_completion;
                }
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
