/**
* Name: Reconnaissance Drone Agent
* Description: BDI cognitive definition for the scouting aerial unit.
*/

model GredosReconDrone
import "parameters.gaml"
import "environment.gaml"
import "infrastructure.gaml"
import "coordinador.gaml"

species recon_drone control: simple_bdi skills: [moving] {

    // --- PHYSICAL ATTRIBUTES ---
    float battery_level <- drone_max_fuel;
    float wind_tolerance <- drone_wind_tolerance;
    int patrol_waypoint_index <- 0;
    list<point> patrol_route <- [];
    int drone_index <- 0; // Identifier for this drone within the fleet

    // --- BDI PREDICATE NAMES ---
    string BASE_BELIEF   <- "at_logistics_base";
    string PATROL_DESIRE <- "patrol_area";
    string REFUEL_DESIRE <- "recharge_battery";

    // --- VISUAL ASPECT ---
    aspect default {
        draw line([{location.x, location.y, location.z},
                   {location.x, location.y, location.z - drone_altitude}])
             color: #red width: 1;
        draw circle(125.0) color: #cyan border: #darkblue;
    }

    // --- INITIALISATION ---
    init {
        speed <- drone_speed;
        drone_index <- int(self);  // Unique identifier based on agent index
        do generate_patrol_route;
        do add_desire(predicate(PATROL_DESIRE));
    }

    // --- REFLEXES ---

    // Keep the drone drone_altitude metres above terrain
    reflex adjust_altitude_to_terrain {
        terrain_cell current_cell <- terrain_cell(location);
        if (current_cell != nil) {
            float current_heading <- heading;
            location <- {location.x, location.y, current_cell.altitude + drone_altitude};
            heading  <- current_heading;
        }
    }

    // --- COGNITIVE PLANS ---

    // PATROL
    plan patrol_area intention: predicate(PATROL_DESIRE) {
        // Low battery → notify peers (Protocol 6) and switch to refuel
        if (battery_level <= (drone_max_fuel * 0.2)) {
            string sector_id <- string(int(location.x / 1000.0)) + "_" + string(int(location.y / 1000.0));
            float battery_percent <- (battery_level / drone_max_fuel) * 100.0;
            
            if (is_centralized_model) {
                write "🔋 [Protocolo 6] Inform(retiradaBateria(sector=" + sector_id + ", bateria=" + int(battery_percent) + "%)) → Coordinador";
                ask one_of(coordinador) {
                    do receive_battery_alert(myself, sector_id, battery_percent);
                }
                write "✓ [Protocolo 6] Confirm(retiradaBateria) confirmado";
            } else {
                write "📡 [Protocolo 6 - P2P] Dron [" + name + "] emite broadcast de batería crítica a pares";
                float broadcast_range <- 2500.0;
                list<recon_drone> nearby_drones <- recon_drone where (each != self and each distance_to self < broadcast_range and each.battery_level > (drone_max_fuel * 0.5));
                
                if (!empty(nearby_drones)) {
                    recon_drone relief <- nearby_drones with_min_of (each distance_to self);
                    write "🤝 [Protocolo 6 - P2P] Dron [" + name + "] delega su ruta de patrulla a [" + relief.name + "]";
                    ask relief {
                        do receive_sector_delegation(myself.patrol_route);
                    }
                } else {
                    write "🚨 [Protocolo 6 - P2P] Dron [" + name + "]: Ningún dron cercano puede asumir el sector.";
                }
            }
            // Remove patrol so recharge becomes the only active desire
            do remove_desire(predicate(PATROL_DESIRE));
            do add_desire(predicate(REFUEL_DESIRE), 2.0);
            return;
        }

        // Suspend if wind too strong
        if (wind_intensity > wind_tolerance) {
            write "Drone [" + name + "]: Wind too strong (" + wind_intensity + " > " + wind_tolerance + "). Hovering.";
            return;
        }

        // Follow patrol route waypoints
        if (!empty(patrol_route) and patrol_waypoint_index < length(patrol_route)) {
            point target_waypoint <- patrol_route[patrol_waypoint_index];
            do goto target: {target_waypoint.x, target_waypoint.y, location.z} speed: speed;
            
            if ({location.x, location.y} distance_to target_waypoint < 50.0) {
                patrol_waypoint_index <- patrol_waypoint_index + 1;
                if (patrol_waypoint_index >= length(patrol_route)) {
                    patrol_waypoint_index <- 0; // Loop back
                }
            }
        }
        battery_level <- battery_level - 1.0;
        if (every(5 #cycles)) {
            do scout_for_wildfire;
        }
    }

    // RECHARGE
    plan recharge_battery intention: predicate(REFUEL_DESIRE) {
        logistics_base target_base <- logistics_base with_min_of (each distance_to self);

        // 2D XY movement pass our own z so the goto vector has no Z component
        do goto target: {target_base.location.x, target_base.location.y, location.z}
             speed: speed;

        point my_pos_2d   <- {location.x, location.y};
        point base_pos_2d <- {target_base.location.x, target_base.location.y};

        if (my_pos_2d distance_to base_pos_2d < 50.0) {
            battery_level <- drone_max_fuel;

            do add_belief(predicate(BASE_BELIEF));
            write "Drone [" + name + "]: Battery recharged. Resuming patrol.";
            do remove_belief(predicate(BASE_BELIEF));

            do remove_desire(predicate(REFUEL_DESIRE));
            do add_desire(predicate(PATROL_DESIRE));
        }
    }

    // --- ACTIONS ---

    action generate_patrol_route {
        // Divide the map into vertical sectors: each drone gets one sector
        float min_x <- 0.0;
        float max_x <- world.shape.width;
        float min_y <- 0.0;
        float max_y <- world.shape.height;
        
        float sector_width <- (max_x - min_x) / float(drone_fleet_size);
        float sweep_spacing <- drone_vision_range * 1.5;
        
        // Calculate this drone's sector
        int sector_index <- int(self) mod drone_fleet_size;
        float sector_start_x <- min_x + (sector_index * sector_width);
        float sector_end_x <- sector_start_x + sector_width;
        
        // Offset within sector for variety
        float offset_x <- mod(sector_index, int(sector_width / sweep_spacing)) * sweep_spacing;
        float current_x <- sector_start_x + offset_x;
        
        bool sweep_up <- (mod(sector_index, 2) = 0);
        
        patrol_route <- [];
        
        loop while: current_x < sector_end_x {
            if (sweep_up) {
                patrol_route <- patrol_route + [{current_x, min_y}];
                patrol_route <- patrol_route + [{current_x, max_y}];
            } else {
                patrol_route <- patrol_route + [{current_x, max_y}];
                patrol_route <- patrol_route + [{current_x, min_y}];
            }
            sweep_up <- !sweep_up;
            current_x <- current_x + sweep_spacing;
        }

    }

	action scout_for_wildfire {
	    geometry vision_area <- circle(drone_vision_range) at_location {location.x, location.y};
	    list<terrain_cell> visible_cells <- terrain_cell overlapping vision_area;
	    list<terrain_cell> burning_cells <- visible_cells where (each.is_burning);
	
	    // Limpiar creencias de focos ya extinguidos
	    loop sb over: get_beliefs_with_name("wildfire_detected") {
	        predicate pred <- predicate(sb);
	        point believed_loc <- point(pred.values["location"]);
	        terrain_cell believed_cell <- terrain_cell closest_to believed_loc;
	        if (believed_cell != nil and !believed_cell.is_burning) {
	            do remove_belief(pred);
	        }
	    }
	
	    if (!empty(burning_cells)) {
	        terrain_cell fire_focus <- burning_cells with_max_of (each.fuel_factor);
	        predicate fire_belief <- predicate("wildfire_detected", ["location"::fire_focus.location]);
	
	        if (!has_belief(fire_belief)) {
	            do add_belief(fire_belief);
	            write "Drone [" + name + "]: Wildfire detected at " + fire_focus.location;
	            do trigger_reporting_protocol(fire_focus.location);
	        }
	    }
	}

    // Protocolo 1 — Notificación de Incendio: Drone notifica con intensidad y combustible
    action trigger_reporting_protocol(point fire_location) {
        terrain_cell fire_cell <- terrain_cell closest_to fire_location;
        float fire_intensity <- (fire_cell != nil) ? fire_cell.fuel_factor : 0.5;
        float fuel_available <- (fire_cell != nil) ? fire_cell.fuel_factor : 0.0;
        
        if (is_centralized_model) {
            write "🔔 [Protocolo 1] Inform(focoDetectado(pos=" + fire_location +
		          ", intensidad=" + fire_intensity + ", combustible=" + fuel_available + ")) → Coordinador";
		    ask one_of(coordinador) {
		        do receive_fire_alert(myself, fire_location, fire_intensity, fuel_available);
		    }
        } else {
        	// Comprobar si algún agente ya tiene este foco asignado (focoAsignado)
		    bool already_covered <- false;
			loop b over: bombero_terrestre {
			    bool b_knows <- false;
			    ask b {
			        b_knows <- has_belief(predicate("wildfire_detected", ["location"::fire_location]));
			    }
			    if (b_knows) {
			        already_covered <- true;
			        break;
			    }
			}
			if (!already_covered) {
			    loop b over: bombero_aereo {
			        bool b_knows <- false;
			        ask b {
			            b_knows <- has_belief(predicate("wildfire_detected", ["location"::fire_location]));
			        }
			        if (b_knows) {
			            already_covered <- true;
			            break;
			        }
			    }
			}
		    if (already_covered) {
		        write "⚙️ [Protocolo 2 - CNP] Foco en " + fire_location + " ya cubierto. Ignorando.";
		        return;
		    }
		    // --- CONTRACT NET PROTOCOL (Modelo Descentralizado) ---
		    write "📢 [Protocolo 2 - CNP] Dron [" + name + "]: CFP(proponerMision(" + fire_location + ")) → broadcast";
		
		    // Fase 1: CFP — recoger pujas de todos los bomberos
		    list<bombero_terrestre> all_ground <- bombero_terrestre where (each.operational_state = "Disponible");
		    list<bombero_aereo>     all_aerial <- bombero_aereo     where (each.operational_state = "Disponible");
		
		    // Mapa agente → coste estimado
		    map<agent, float> bids <- map([]);
		
		    loop b over: all_ground {
		        float bid <- 0.0;
		        ask b { bid <- calculate_bid(fire_location); }
		        if (bid < #max_float) {
		            bids[b] <- bid;
		            write "   Propose [" + b.name + "]: coste=" + int(bid);
		        }
		    }
		    loop b over: all_aerial {
		        float bid <- 0.0;
		        ask b { bid <- calculate_bid(fire_location); }
		        if (bid < #max_float) {
		            bids[b] <- bid;
		            write "   Propose [" + b.name + "]: coste=" + int(bid);
		        }
		    }
		
		    // Fase 2: selección — el iniciador elige la puja con menor coste
		    if (empty(bids)) {
		        write "🚨 [Protocolo 2 - CNP] Sin candidatos válidos para foco en " + fire_location;
		    } else {
		        agent winner <- bids.keys with_min_of (bids[each]);
		        float winning_bid <- bids[winner];
		
		        write "🏆 [Protocolo 2 - CNP] Ganador: [" + winner.name + "] con coste=" + int(winning_bid);
		
		        // Fase 3: Accept-Proposal al ganador, Reject-Proposal al resto
		        if (winner is bombero_terrestre) {
				    ask bombero_terrestre(winner) {
				        write "✅ Accept-Proposal(aceptarCompromiso(" + fire_location + ")) → [" + name + "]";
				        do request_mission(fire_location);
				    }
				} else if (winner is bombero_aereo) {
				    ask bombero_aereo(winner) {
				        write "✅ Accept-Proposal(aceptarCompromiso(" + fire_location + ")) → [" + name + "]";
				        do request_mission(fire_location);
				    }
				}
		        loop loser over: bids.keys where (each != winner) {
		            write "❌ Reject-Proposal(aceptarCompromiso(" + fire_location + ")) → [" + loser.name + "]";
		        }
		    }
	    }
    }

    // Protocolo 6: Asumir la ruta de un dron que se retira a recargar
    action receive_sector_delegation(list<point> orphaned_route) {
        loop pt over: orphaned_route {
            if (!(pt in patrol_route)) {
                patrol_route <- patrol_route + [pt];
            }
        }
        write "📡 [Protocolo 6] Dron [" + name + "]: Sector huérfano asumido. Puntos de ruta ampliados a " + length(patrol_route);
    }
    
    // Protocolo 9: Recibir notificación de foco extinguido para limpiar creencias
    action receive_mission_completion(point extinguished_fire) {
    loop sb over: get_beliefs_with_name("wildfire_detected") {
        predicate pred <- predicate(sb);
        point believed_loc <- point(pred.values["location"]);
        if (believed_loc distance_to extinguished_fire < 150.0) {
            do remove_belief(pred);
            write "🧹 [Protocolo 9] Dron [" + name + "]: Foco " + extinguished_fire + " eliminado de memoria.";
        }
    }
}
}
