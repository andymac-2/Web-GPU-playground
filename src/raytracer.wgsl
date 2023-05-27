@group(0) @binding(0)
var<storage, read_write> buffer: array<f32>;

@group(0) @binding(1)
var<uniform> column: u32;

const epsilon = 0.001;
const order_of_magnitude = 10.0;
const pi = 3.14159265;

const camera_position = vec3<f32>(-7.0, -2.0, -7.0);

const color_sun = vec3<f32>(2.2, 1.8, 2.2);
const color_wall = vec3<f32>(0.9, 0.9, 0.6);
const color_black = vec3<f32>(0.0, 0.0, 0.0);

const hit_none = 0u;
const hit_wall = 1u;
const hit_sun = 2u;
const hit_box = 3u;

const image_height = 512;
const image_width = 1024;

const vec_zero = vec3<f32>(0.0, 0.0, 0.0);
const vec_one = vec3<f32>(1.0, 1.0, 1.0);
const vec_up = vec3<f32>(0.0, 1.0, 0.0);
const vec_down = vec3<f32>(0.0, -1.0, 0.0);
const vec_forward = vec3<f32>(1.0, 0.0, 0.0);
const vec_backward = vec3<f32>(-1.0, 0.0, 0.0);
const vec_left = vec3<f32>(0.0, 0.0, -1.0);
const vec_right = vec3<f32>(0.0, 0.0, 1.0);

struct Box {
    top: vec3<f32>,
    bottom: vec3<f32>,
    hit_type: u32,
}

struct Collision {
    position: vec3<f32>,
    normal: vec3<f32>,
    hit_type: u32,
}

struct Ray {
    start: vec3<f32>,
    direction: vec3<f32>,
}

fn buffer_pixel_index(x: u32, y: u32) -> u32 {
    return (y * u32(image_width) + x) * u32(3);
}

fn buffer_set_color(index: u32, color: vec3<f32>) {
    buffer[index + 0u] = abs(color.x);
    buffer[index + 1u] = abs(color.y);
    buffer[index + 2u] = abs(color.z);
}

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

fn collision_all(ray: Ray) -> Collision {
    return collision_min(
        ray.start,
        collision_room(ray),
        collision_sun(ray),
    );
}

fn collision_box(box: Box, ray: Ray) -> Collision {
    let tBottom = (box.bottom - ray.start) / ray.direction;
    let tTop = (box.top - ray.start) / ray.direction;

    let tMin = min(tTop, tBottom);
    let tMax = max(tTop, tBottom);

    let tEnter = max(tMin.x, max(tMin.y, tMin.z));
    let tExit = min(tMax.x, min(tMax.y, tMax.z));

    // no collision or collision behind the ray
    if tExit < tEnter || tExit < 0.0 {
        return Collision (vec_zero, vec_zero, hit_none);
    }

    var tCollision = tEnter;
    // Ray originated inside box
    if tEnter < 0.0 {
        tCollision = tExit;
    }

    let position = tCollision * ray.direction + ray.start;

    if tCollision == tBottom.x {
        return Collision (position, vec_backward, box.hit_type);
    } else if tCollision == tTop.x {
        return Collision (position, vec_forward, box.hit_type);
    } else if tCollision == tBottom.y {
        return Collision (position, vec_down, box.hit_type);
    } else if tCollision == tTop.y {
        return Collision (position, vec_up, box.hit_type);
    } else if tCollision == tBottom.z {
        return Collision (position, vec_left, box.hit_type);
    } else if tCollision == tTop.z {
        return Collision (position, vec_right, box.hit_type);
    }

    return Collision (vec_zero, vec_zero, hit_none);
}

fn collision_interior(collision: Collision) -> Collision {
    return Collision(collision.position, -collision.normal, collision.hit_type);
}

fn collision_min(start: vec3<f32>, a: Collision, b: Collision) -> Collision {
    if a.hit_type == hit_none {
        return b;
    }

    if b.hit_type == hit_none {
        return a;
    }

    if length(start - a.position) < length(start - b.position) {
        return a;
    } else {
        return b;
    }
}

fn collision_room(ray: Ray) -> Collision {
    let corner_box = Box(
        vec3<f32>(4.0, 5.0, 10.0),
        vec3<f32>(-4.0, -5.0, 0.0),
        hit_wall
    );
    let room = Box(
        vec3<f32>(10.0, 5.0, 10.0),
        vec3<f32>(-10.0, -5.0, -10.0),
        hit_wall
    );
    return collision_min(
        ray.start,
        collision_interior(collision_box(room, ray)),
        collision_box(corner_box, ray)
    );
}

fn collision_sun(ray: Ray) -> Collision {
    let sun = Box(
        vec3<f32>(13.0, 5.0, 6.0),
        vec3<f32>(1.0, -5.0, 4.0),
        hit_sun
    );
    return collision_box(sun, ray);
}

fn diffuse_direction(normal: vec3<f32>) -> vec3<f32> {
    let random_ray = rng_surface_unit_sphere();
    if dot(random_ray, normal) > 0.0 {
        return random_ray;
    } else {
        return -random_ray;
    }
}

fn get_color(start_ray: Ray) -> vec3<f32> {
    let sun_direction = normalize(vec3<f32>(0.5, 0.2, 1.0));

    var attenuation = vec_one;
    var brightness = color_black;

    var ray = start_ray;

    for (var bounce_count = 0; bounce_count < 4; bounce_count++) {
        let collision = collision_all(ray);
        ray.start = collision.position + collision.normal * order_of_magnitude * epsilon;

        if collision.hit_type == hit_sun {
            return color_sun * attenuation + brightness;
        } else if collision.hit_type == hit_wall {
            if collision_all(Ray(ray.start, sun_direction)).hit_type == hit_sun {
                brightness += dot(sun_direction, collision.normal) * color_sun * attenuation;
            }

            attenuation *= color_wall;
            ray.direction = diffuse_direction(collision.normal);
        } else {
            return brightness;
        }
    }

    return brightness;
}

@compute
@workgroup_size(1, 1, 1)
fn main(@builtin(global_invocation_id) global_id: vec3<u32>) {
    let sample_count = 64u;
    let index = buffer_pixel_index(column, global_id.y);
    rng_seed(index);

    let destination = camera_ray_destination(column, global_id.y);

    var color = color_black;
    for (var rays = 0u; rays < sample_count; rays++) {
        let source = camera_ray_source();
        color += get_color(Ray(source, normalize(destination - source)));
    }
    color /= f32(sample_count);

    buffer_set_color(index, color);
}

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

fn sdf_box(point: vec3<f32>, size: vec3<f32>) -> f32 {
    let dist = abs(point) - size;
    return min(max(dist.x, max(dist.y, dist.z)), 0.0) + length(max(dist, vec_zero));
}
