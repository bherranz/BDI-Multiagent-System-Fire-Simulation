/**
* Name: Static Infrastructure
* Description: Roads, water points and logistics bases.
*/
model GredosInfrastructure

import "parameters.gaml"
import "environment.gaml" 

species road {
    aspect default { draw shape color: COLOR_ROAD width: 2; }

    action mark_cells {
        ask terrain_cell overlapping self {
            has_road <- true;
        }
    }
}

species water_point {
    aspect default { draw circle(50) color: COLOR_WATER border: #darkblue; }

    action mark_cells {
        ask terrain_cell overlapping self {
            has_water <- true;
        }
    }
}

species logistics_base {
    aspect default { draw square(150) color: COLOR_BASE border: #black; }
}
