@group(0) @binding(0)
var<storage, read_write> buffer: array<f32>;

@group(0) @binding(1)
var<uniform> column: u32;

const image_width = 1024;
const image_height = 512;

const epsilon = 0.001;
const pi = 3.14159265;
const order_of_magnitude = 10.0;

const vec_zero = vec3<f32>(0.0, 0.0, 0.0);
const vec_up = vec3<f32>(0.0, 1.0, 0.0);
const vec_one = vec3<f32>(1.0, 1.0, 1.0);

const color_sun = vec3<f32>(2.2, 1.8, 2.2);
const color_wall = vec3<f32>(0.9, 0.9, 0.6);
const color_black = vec3<f32>(0.0, 0.0, 0.0);

const hit_none = 0u;
const hit_wall = 1u;
const hit_sun = 2u;

struct Collision {
    position: vec3<f32>,
    normal: vec3<f32>,
    hit_type: u32,
}

struct QueryResult {
    distance: f32,
    hit_type: u32,
}

fn buffer_pixel_index(x: u32, y: u32) -> u32 {
    return (y * u32(image_width) + x) * u32(3);
}

fn buffer_set_color(index: u32, color: vec3<f32>) {
    buffer[index + 0u] = abs(color.x);
    buffer[index + 1u] = abs(color.y);
    buffer[index + 2u] = abs(color.z);
}

// CAMERA

const camera_position = vec3<f32>(-7.0, -2.0, -7.0);

fn camera_ray_destination(x: u32, y: u32) -> vec3<f32> {
    let fisheye_factor = 0.8;
    let camera_focal_point = vec3<f32>(0.0, 0.0, 3.0);

    // transform x and y into from integer to a float between -1 and 1
    let normalized_x = f32(x) * 2.0 / f32(image_height) - f32(image_width) / f32(image_height);
    let normalized_y = f32(y) * 2.0 / f32(image_height) - 1.0;

    let theta = length(vec2<f32>(normalized_x, normalized_y)) * fisheye_factor;
    var phi = 0.0;
    if normalized_y != 0.0 {
        phi = atan2(normalized_x, normalized_y);
    } else if normalized_x < 0.0 {
        phi = pi * 1.5;
    } else {
        phi = pi * 0.5;
    }

    let sin_theta = sin(theta);
    let normalized_aim = vec3<f32>(cos(theta), sin_theta * cos(phi), sin_theta * sin(phi));

    let forwards = camera_focal_point - camera_position;
    let forwards_length = length(forwards);
    let right = normalize(cross(forwards, vec_up)) * forwards_length;
    let up = normalize(cross(forwards, right)) * forwards_length;

    // colum major
    let transform = mat3x3<f32>(forwards, up, right);
    return transform * normalized_aim + camera_position;
}

fn camera_ray_source() -> vec3<f32> {
    let aperture_size = 0.5;
    return camera_position + rng_unit_cube() * aperture_size;
}

fn diffuse_ray(normal: vec3<f32>) -> vec3<f32> {
    let random_ray = rng_surface_unit_sphere();
    if dot(random_ray, normal) > 0.0 {
        return random_ray;
    } else {
        return -random_ray;
    }
}

fn get_collision(start: vec3<f32>, direction: vec3<f32>) -> Collision {
    let normalized_direction = normalize(direction);
    var position = start;
    var query_result = QueryResult(0.0, hit_none);
    loop {
        query_result = query_all(position);
        if query_result.distance < epsilon {
            break;
        }

        position += normalized_direction * query_result.distance;
    }

    let normal = normalize(vec3<f32>(
        query_result.distance - query_all(position - vec3<f32>(epsilon, 0.0, 0.0)).distance,
        query_result.distance - query_all(position - vec3<f32>(0.0, epsilon, 0.0)).distance,
        query_result.distance - query_all(position - vec3<f32>(0.0, 0.0, epsilon)).distance,
    ));
    return Collision(position, normal, query_result.hit_type);
}

fn get_color(start_position: vec3<f32>, start_direction: vec3<f32>) -> vec3<f32> {
    let sun_direction = normalize(vec3<f32>(0.5, 0.2, 1.0));

    var attenuation = vec_one;
    var brightness = color_black;

    var position = start_position;
    var direction = start_direction;

    for (var bounce_count = 0; bounce_count < 4; bounce_count++) {
        let collision = get_collision(position, direction);
        position = collision.position + collision.normal * order_of_magnitude * epsilon;

        if collision.hit_type == hit_sun {
            return color_sun * attenuation + brightness;
        } else if collision.hit_type == hit_wall {
            if get_collision(position, sun_direction).hit_type == hit_sun {
                brightness += dot(sun_direction, collision.normal) * color_sun * attenuation;
            }

            attenuation *= color_wall;
            direction = diffuse_ray(collision.normal);
            position += direction * order_of_magnitude * epsilon;
        } else {
            return brightness;
        }
    }

    return brightness;
}

fn query_all(point: vec3<f32>,) -> QueryResult {
    return query_min(query_room(point), query_sun(point));
}

fn query_min(a: QueryResult, b: QueryResult) -> QueryResult {
    if a.distance < b.distance {
        return a;
    } else {
        return b;
    }
}

fn query_room(point: vec3<f32>) -> QueryResult {
    let room_size = vec3<f32>(10.0, 5.0, 10.0);
    let corner_box_size = vec3<f32>(4.0, 5.0, 5.0);
    let corner_box_position = vec3<f32>(0.0, 0.0, 5.0);
    return QueryResult(
        min(
            -sdf_box(point, room_size),
            sdf_box(point - corner_box_position, corner_box_size)
        ),
        hit_wall
    );
}

fn query_sun(point: vec3<f32>) -> QueryResult {
    let sun_size = vec3<f32>(6.0, 5.0, 1.0);
    let sun_position = vec3<f32>(7.0, 0.0, 5.0);
    return QueryResult(
        sdf_box(point - sun_position, sun_size),
        hit_sun
    );
}

fn sdf_box(point: vec3<f32>, size: vec3<f32>) -> f32 {
    let dist = abs(point) - size;
    return min(max(dist.x, max(dist.y, dist.z)), 0.0) + length(max(dist, vec_zero));
}

@compute
@workgroup_size(1, 1, 1)
fn main(@builtin(global_invocation_id) global_id: vec3<u32>) {
    let sample_count = 256u;
    let index = buffer_pixel_index(column, global_id.y);
    rng_seed(index);

    let destination = camera_ray_destination(column, global_id.y);

    var color = color_black;
    for (var rays = 0u; rays < sample_count; rays++) {
        let source = camera_ray_source();
        color += get_color(source, destination - source);
    }
    color /= f32(sample_count);

    buffer_set_color(index, color);
}

// RNG

var<private> rng_state: u32 = 0u;
fn rng_seed(number: u32) {
    rng_state = number;
    rng_get();
}

fn rng_get() -> f32 {
    rng_state ^= rng_state << 13u;
    rng_state ^= rng_state >> 17u;
    rng_state ^= rng_state << 5u;
    return f32(rng_state) / f32(0xFFFFFFFFu);
}

fn rng_surface_unit_sphere() -> vec3<f32> {
    let latitude = rng_get() * 2.0 - 1.0;
    let longditude = rng_get() * 2.0 * pi;
    let radius = sqrt(1.0 - latitude * latitude);
    return vec3<f32>(sin(longditude) * radius, cos(longditude) * radius, latitude);
}

fn rng_unit_cube() -> vec3<f32> {
    return vec3<f32>(rng_get(), rng_get(), rng_get()) - vec3<f32>(0.5, 0.5, 0.5);
}
