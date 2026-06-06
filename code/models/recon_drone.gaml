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
            string sector_id <- string(int(location.x)) + "_" + string(int(location.y));
            write "Drone [" + name + "]: Low battery. Protocol 6 — broadcasting retiradaBateria(" + sector_id + ")";
            if (is_centralized_model) {
                write "[CENTRALIZED] Inform(retiradaBateria(" + sector_id + ")) → Coordinator";
            } else {
                write "[DECENTRALIZED] Broadcast Inform(retiradaBateria(" + sector_id + "))";
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

        // Follow patrol route waypoints (sweep pattern instead of wander)
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
        do scout_for_wildfire;
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

        if (!empty(burning_cells)) {
            // Prioritise the most flammable burning cell in the scan radius
            terrain_cell fire_focus <- burning_cells with_max_of (each.fuel_factor);
            predicate fire_belief   <- predicate("wildfire_detected",
                                                 ["location"::fire_focus.location]);

            if (!has_belief(fire_belief)) {
                do add_belief(fire_belief);
                write "Drone [" + name + "]: Wildfire detected at " + fire_focus.location;
                do trigger_reporting_protocol(fire_focus.location);
            }
        }
    }

    // Protocol 1 — centralised: unicast to Coordinator / decentralised: broadcast
    action trigger_reporting_protocol(point fire_location) {
        if (is_centralized_model) {
            write "🔔 [Protocol 1] Inform(focoDetectado) → Coordinator";
            ask one_of(coordinador) {
                do receive_fire_alert(fire_location);
            }
            write "✓ [Protocol 1] Confirm(focoDetectado) received";
        } else {
            write "[DECENTRALIZED — Protocol 1] Broadcast Inform(focoDetectado)";
            // TODO: ask firefighters at_distance comm_range { do receive_fire_report(fire_location); }
        }
    }
}
