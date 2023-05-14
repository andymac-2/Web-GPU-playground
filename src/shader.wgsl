@group(0)
@binding(0)
var<storage> signal: array<vec2<f32>>;

@group(0)
@binding(1)
var<storage, read_write> frequencies: array<vec2<f32>>;

const pi = 3.14159265;

fn complex_add(a: vec2<f32>, b: vec2<f32>) -> vec2<f32> {
    return vec2<f32>(a.x + b.x, a.y + b.y);
}

fn complex_mul(a: vec2<f32>, b: vec2<f32>) -> vec2<f32> {
    return vec2<f32>(a.x * b.x - a.y * b.y, a.x * b.y + a.y * b.x);
}

fn complex_exp(a: f32) -> vec2<f32> {
    return vec2<f32>(cos(a), sin(a));
}

fn fourier(index: u32) -> vec2<f32> {
    let size = arrayLength(&signal);
    var sum = vec2<f32>(0.0, 0.0);
    for (var n: i32 = 0; n < i32(size); n++) {
        sum = complex_add(
            sum,
            complex_mul(
                signal[n],
                complex_exp(-2.0 * pi * f32(index) * f32(n) / f32(size))
            )
        );
    }

    return sum;
}

@compute
@workgroup_size(1)
fn main(@builtin(global_invocation_id) global_id: vec3<u32>) {
    frequencies[global_id.x] = fourier(global_id.x);
}