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
    float wind_exposure     <- 0.0;
    // Disponible | En vuelo | Extinguiendo | Repostando | Recargando agua | Retirada
    string operational_state <- "Disponible";

    // Target assigned by Coordinator (Protocol 2)
    point assigned_target_location <- nil;
    // Referencia para calcular progreso real (Protocolo 3)
	int initial_fire_count <- 0;
	// Mapa local de creencias sobre focos (Protocolo 3 - Modelo Descentralizado)
	map<point, string> known_fires_local <- map([]);
	bool reinforcement_requested <- false;
	bool withdrawal_notified <- false;
	bool fuel_refuel_notified <- false;
	bool emergency_notified <- false;

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

    // Protocolo 2: Evaluación de misión y negociación BDI
    action request_mission(point target_location) {
        // Evaluate BDI state: water, fuel, wind
        float water_margin <- water_load - (aerial_firefighter_max_water * 0.2);
        float fuel_margin <- fuel_level - (aerial_firefighter_max_fuel * 0.25); // Need 25% to return to base
        float wind_margin <- aerial_firefighter_wind_tolerance - wind_intensity;

        bool can_accept <- (water_margin > 0 and fuel_margin > 0 and wind_margin > 0.5);
        
        if (can_accept) {
		    write "🟢 [Protocolo 2] Bombero [" + name + "]: AGREE — Aceptando misión en " + target_location;
		    assigned_target_location <- target_location;
		    geometry initial_zone <- circle(120.0) at_location target_location;
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
            write "🔴 [Protocolo 2] Helicóptero [" + name + "]: REFUSE — No puede aceptar (agua: " + int(water_load) + "L, combustible: " + int(fuel_level) + ", viento: " + wind_intensity + ")";
        }
    }
    
    // Protocolo 2 CNP: calcular y devolver coste estimado para una puja
	action calculate_bid(point target_location) type: float {
	    float distance_cost <- location distance_to target_location;
	    float water_penalty <- (1.0 - (water_load / aerial_firefighter_max_water)) * 3000.0;
	    float fuel_penalty  <- (1.0 - (fuel_level  / aerial_firefighter_max_fuel))  * 8000.0;
	    float wind_penalty  <- (wind_intensity > aerial_firefighter_wind_tolerance) ? #max_float : 0.0;
	    
	    if (operational_state != "Disponible") {
	        return #max_float;
	    }
	
	    return distance_cost + water_penalty + fuel_penalty + wind_penalty;
	}
    
    // Protocolo 3: Informe de estado y progreso periódico
    action report_status_to_coordinator {
	    string fire_state <- "activo";
	    geometry search_zone <- circle(200.0) at_location assigned_target_location;
	    list<terrain_cell> nearby_fires <- (terrain_cell overlapping search_zone) where (each.is_burning);
	    if (empty(nearby_fires)) { fire_state <- "controlado"; }
	
	    geometry mission_zone <- circle(200.0) at_location assigned_target_location;
	    int current_fire_count <- length((terrain_cell overlapping mission_zone) where (each.is_burning));
	    
	    float progress <- (initial_fire_count > 0)
	        ? max(0.0, min(100.0, (1.0 - (float(current_fire_count) / float(initial_fire_count))) * 100.0))
	        : 100.0;
	        
	    write "📊 [Protocolo 3] Helicóptero [" + name + "]: Inform(focoActualizado(estado=" + fire_state
	        + ", progreso=" + int(progress) + "%, agua=" + int(water_load) + "L, fuel=" + int(fuel_level) + "L))";
	        
	    if (is_centralized_model) {
	        ask one_of(coordinador) {
	            do receive_status_update(myself, myself.assigned_target_location, fire_state, progress, myself.water_load, myself.fuel_level);
	        }
	    } else {
		    float broadcast_range <- 500.0;
		    list<bombero_terrestre> nearby_ground <- bombero_terrestre where
		        (each distance_to self < broadcast_range);
		    list<bombero_aereo> nearby_aerial <- bombero_aereo where
		        (each != self and each distance_to self < broadcast_range);
		    ask nearby_ground {
		        do receive_status_broadcast(myself.assigned_target_location, fire_state, progress);
		    }
		    ask nearby_aerial {
		        do receive_status_broadcast(myself.assigned_target_location, fire_state, progress);
		    }
		}
	}
	
	// Protocolo 3 P2P: recibir actualización de estado de un par
	action receive_status_broadcast(point fire_location, string fire_state, float progress) {
	    known_fires_local[fire_location] <- fire_state;
	    write "📡 [Protocolo 3 - P2P] Bombero [" + name + "]: Sincroniza foco "
	        + fire_location + " → " + fire_state + " (" + int(progress) + "%)";
	}
	
	// Protocolo 4: Petición de refuerzos
    action request_reinforcements {
        if (reinforcement_requested) { return; }

        geometry search_zone <- circle(250.0) at_location {location.x, location.y};
        list<terrain_cell> nearby_fires <- (terrain_cell overlapping search_zone) where (each.is_burning);
        float fire_count <- float(length(nearby_fires));

        // El helicóptero pide ayuda si el fuego es grande (>15) y le queda poca agua
        if (fire_count > 15.0 and water_load < aerial_firefighter_max_water * 0.3) {
            write "⚠️ [Protocolo 4] Helicóptero [" + name + "]: Request(ayudar(foco=" + assigned_target_location + "))";
            
            if (is_centralized_model) {
                ask one_of(coordinador) {
                    do receive_reinforcement_request(myself, myself.assigned_target_location, fire_count);
                }
            } else {
                float broadcast_range <- 800.0; // Tienen más alcance de radio
                list<bombero_terrestre> nearby_ground <- bombero_terrestre where (each distance_to self < broadcast_range);
                list<bombero_aereo> nearby_aerial <- bombero_aereo where (each != self and each distance_to self < broadcast_range);
                
                ask nearby_ground { do request_mission(myself.assigned_target_location); }
                ask nearby_aerial { do request_mission(myself.assigned_target_location); }
            }
            reinforcement_requested <- true;
        }
    }
    
    // Protocolo 5: Notificación de retirada para recarga de agua
    action notify_water_withdrawal {
        if (assigned_target_location != nil) {
            write "💧 [Protocolo 5] Helicóptero [" + name + "]: Inform(retiradaRecarga(foco=" + assigned_target_location + "))";
            if (is_centralized_model) {
                ask one_of(coordinador) {
                    do receive_withdrawal_notification(myself, myself.assigned_target_location, "water_refill");
                }
            } else {
                // Modelo descentralizado: Broadcast masivo
                float broadcast_range <- 1000.0;
                list<bombero_aereo> nearby_aerial <- bombero_aereo where (each != self and each distance_to self < broadcast_range);
                list<bombero_terrestre> nearby_ground <- bombero_terrestre where (each distance_to self < broadcast_range);
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
    
    // Protocolo 7: Repostaje de combustible y delegación de foco
    action notify_fuel_refueling {
        if (assigned_target_location != nil) {
            write "⛽ [Protocolo 7] Helicóptero [" + name + "]: Inform(retiradaFuel(foco=" + assigned_target_location + "))";
            
            if (is_centralized_model) {
                ask one_of(coordinador) {
                    do receive_fuel_refuel_request(myself, myself.assigned_target_location);
                }
            } else {
                // Modelo descentralizado: Broadcast para cubrir el fuego
                float broadcast_range <- 1000.0;
                list<bombero_aereo> nearby_aerial <- bombero_aereo where (each != self and each distance_to self < broadcast_range);
                list<bombero_terrestre> nearby_ground <- bombero_terrestre where (each distance_to self < broadcast_range);
                list<recon_drone> nearby_drones <- recon_drone where (each distance_to self < broadcast_range);
                
                ask nearby_drones {
                    if (!(myself.assigned_target_location in patrol_route)) {
                        patrol_route <- [myself.assigned_target_location] + patrol_route;
                    }
                }
                geometry target_zone <- circle(150.0) at_location assigned_target_location;
				bool fire_still_active <- !empty((terrain_cell overlapping target_zone) where (each.is_burning));
				
				if (fire_still_active) {
				    ask nearby_aerial { do request_mission(myself.assigned_target_location); }
				    ask nearby_ground { do request_mission(myself.assigned_target_location); }
				} else {
				    write "ℹ️ [Protocolo 7 - P2P] Foco en " + assigned_target_location + " ya extinguido. No se envía relevo.";
				}
            }
        }
    }
    
    // Protocolo 8: Evacuación de emergencia por seguridad crítica
    action emergency_evacuation_protocol {
        write "🚨 [Protocolo 8] Helicóptero [" + name + "]: Inform(retiradaEmergencia(condición_crítica))";
        operational_state <- "Retirada";
        
        if (assigned_target_location != nil) {
            if (is_centralized_model) {
                ask one_of(coordinador) {
                    do receive_emergency_evacuation(myself, myself.assigned_target_location, 0.0);
                }
            } else {
                // Modelo descentralizado: Broadcast masivo
                float broadcast_range <- 1000.0;
                list<bombero_aereo> nearby_aerial <- bombero_aereo where (each != self and each distance_to self < broadcast_range);
                list<bombero_terrestre> nearby_ground <- bombero_terrestre where (each distance_to self < broadcast_range);
                list<recon_drone> nearby_drones <- recon_drone where (each distance_to self < broadcast_range);
                
                ask nearby_drones {
                    if (!(myself.assigned_target_location in patrol_route)) {
                        patrol_route <- [myself.assigned_target_location] + patrol_route;
                    }
                }
                ask nearby_aerial { do request_mission(myself.assigned_target_location); }
                ask nearby_ground { do request_mission(myself.assigned_target_location); }
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
        
        do remove_desire(predicate(EXTINGUISH_DESIRE));
    }

    // --- REFLEXES ---

    // Protocolo 3: Reportes periódicos de estado
    reflex protocol_3_periodic_status when: (operational_state = "Extinguiendo" or operational_state = "En vuelo") 
    and assigned_target_location != nil 
    and (int(cycle) mod 5 = 0) {
        do report_status_to_coordinator;
    }
    
    // Protocolo 4: Detectar necesidad de refuerzos
    reflex protocol_4_check_reinforcements when: (operational_state = "Extinguiendo" or operational_state = "En vuelo") 
    and assigned_target_location != nil 
    and (int(cycle) mod 7 = 0) {
        do request_reinforcements;
    }

    reflex adjust_altitude_to_terrain {
        // Helicopters maintain altitude ABOVE terrain
        terrain_cell current_cell <- terrain_cell(location);
        if (current_cell != nil) {
            float min_altitude <- current_cell.altitude + aerial_firefighter_cruise_altitude;
            location <- {location.x, location.y, min_altitude};
        }
    }

    reflex consume_fuel {
	    if (operational_state != "Disponible" 
	        and operational_state != "Repostando"
	        and operational_state != "Retirada") {
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

    reflex evaluate_resources when: operational_state = "Extinguiendo" or operational_state = "En vuelo" {
        // Protocolo 5: Water critical (Agua baja)
        if (water_load <= (aerial_firefighter_max_water * 0.15) and !has_desire(predicate(REFUEL_WATER_DESIRE))) {
            operational_state <- "Recargando";
            do remove_desire(predicate(EXTINGUISH_DESIRE)); // Soltamos la misión
            do add_desire(predicate(REFUEL_WATER_DESIRE), 5.0); // Prioridad máxima
            write "💧 Helicóptero [" + name + "]: WATER LOW (" + int(water_load) + "L). Necesita recarga.";
        }
        
        // Protocolo 7: Fuel critical (Combustible bajo)
        if (fuel_level <= (aerial_firefighter_max_fuel * 0.25) and !has_desire(predicate(REFUEL_FUEL_DESIRE))) {
            operational_state <- "Repostando";
            do remove_desire(predicate(EXTINGUISH_DESIRE)); // Soltamos la misión
            do add_desire(predicate(REFUEL_FUEL_DESIRE), 5.0); // Prioridad máxima
            write "⛽ Helicóptero [" + name + "]: FUEL LOW (" + int(fuel_level) + "L). Solicitando repostaje.";
        }
    }

    // --- COGNITIVE PLANS ---

    plan tactical_retreat intention: predicate(SURVIVAL_DESIRE) {
        if (!emergency_notified) {
            do emergency_evacuation_protocol;
            assigned_target_location <- nil;
            emergency_notified <- true;
        }
        logistics_base safe_zone <- logistics_base with_min_of (each distance_to self);
        
        if (safe_zone != nil) {
            do goto target: {safe_zone.location.x, safe_zone.location.y, safe_zone.location.z + 50.0} speed: speed;
            
            if ({location.x, location.y} distance_to {safe_zone.location.x, safe_zone.location.y} < 100.0) {
                wind_exposure <- 0.0;
                operational_state <- "Disponible";
                emergency_notified <- false; // Reset
                do remove_desire(predicate(SURVIVAL_DESIRE));
                write "🚁 Helicóptero [" + name + "]: Safe at base. Status normalized.";
            }
        }
    }

    plan refuel_fuel intention: predicate(REFUEL_FUEL_DESIRE) {
        // Enviar notificación solo 1 vez
        if (!fuel_refuel_notified) {
            do notify_fuel_refueling;
            fuel_refuel_notified <- true;
        }
        logistics_base target_base <- logistics_base with_min_of (each distance_to self);
        if (target_base != nil) {
            // Negociación de turno de aterrizaje P2P
            if (!is_centralized_model) {
                list<bombero_aereo> ocupantes <- bombero_aereo where (each != self and each.operational_state = "Repostando" and each distance_to target_base < 100.0);
                if (!empty(ocupantes)) {
                    write "🚁 [Protocolo 7 - P2P] Base ocupada por [" + ocupantes[0].name + "]. [" + name + "] entra en patrón de espera.";
                    // Se mueve en círculos lentamente esperando su turno
                    do goto target: {location.x + rnd(-30, 30), location.y + rnd(-30, 30), location.z} speed: speed * 0.3;
                    return; // Aborta este ciclo y vuelve a intentarlo en el siguiente
                }
            }
            // Si está libre, entra a repostar
            operational_state <- "Repostando";
            do goto target: {target_base.location.x, target_base.location.y, target_base.location.z + 50.0} speed: speed;
            
            if ({location.x, location.y} distance_to {target_base.location.x, target_base.location.y} < 100.0) {
                fuel_level <- aerial_firefighter_max_fuel;
                operational_state <- "Disponible";
                fuel_refuel_notified <- false; // Reseteamos semáforo
                assigned_target_location <- nil;
                do remove_desire(predicate(REFUEL_FUEL_DESIRE));
                write "⛽ Helicóptero [" + name + "]: Fuel tank refilled. Ready for operations.";
            }
        }
    }

    plan refuel_water intention: predicate(REFUEL_WATER_DESIRE) {
        // Protocolo 5: Notificar retirada para recarga de agua
        if (!withdrawal_notified) {
            do notify_water_withdrawal;
            withdrawal_notified <- true;
        }
        
        water_point nearest_water <- water_point with_min_of (each distance_to self);
        if (nearest_water != nil) {
            do goto target: {nearest_water.location.x, nearest_water.location.y, nearest_water.location.z + 50.0} speed: speed;
            
            if ({location.x, location.y} distance_to {nearest_water.location.x, nearest_water.location.y} < 80.0) {
                water_load <- aerial_firefighter_max_water;
                operational_state <- "Disponible";
                withdrawal_notified <- false;
                assigned_target_location <- nil;
                
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
                // Apagar agresivamente los fuegos en el radio corto
                loop fire_cell over: fires_to_extinguish {
                    float water_use <- 8.0;
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

    reflex debug_helicopter when: assigned_target_location != nil 
    and operational_state = "En vuelo" 
    and (int(cycle) mod 10 = 0) {
        float dist_to_target <- {location.x, location.y} distance_to assigned_target_location;
        write "[AERIAL] Helicóptero [" + name + "]: Distance to target = " + int(dist_to_target) + "m. Fuel: " + int(fuel_level) + "L, Water: " + int(water_load) + "L";
    }
}
