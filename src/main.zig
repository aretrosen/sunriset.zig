const std = @import("std");
const zmath = std.math;
const ctime = @cImport({
    @cDefine("_POSIX_C_SOURCE", "200809L");
    @cInclude("time.h");
});

pub const TimeError = error{
    ClockGetTime,
    GMTime,
    LocalTime,
};

pub fn get_now_UT() !f64 {
    var ts: ctime.struct_timespec = .{};
    const err = ctime.clock_gettime(ctime.CLOCK_REALTIME, &ts);
    if (err == -1) {
        return TimeError.ClockGetTime;
    }
    return @as(f64, @floatFromInt(ts.tv_sec)) + @as(f64, @floatFromInt(ts.tv_nsec)) / 1_000_000_000.0;
}

pub fn get_local_tz_offset() !i32 {
    const frac_ut_time = try get_now_UT();
    const tt: ctime.time_t = @as(c_long, @intFromFloat(@round(frac_ut_time)));
    var utc_tm: ctime.struct_tm = .{};
    var err = ctime.gmtime_r(&tt, &utc_tm);
    if (err == null) {
        return TimeError.GMTime;
    }
    var local_tm: ctime.struct_tm = .{};
    err = ctime.localtime_r(&tt, &local_tm);
    if (err == null) {
        return TimeError.LocalTime;
    }
    return @as(i32, (local_tm.tm_hour - utc_tm.tm_hour) * 60 + local_tm.tm_min - utc_tm.tm_min) * 60;
}

pub inline fn calcTimeJulianCent(jd: f64) f64 {
    return (jd - 245145.0) / 36525.0;
}

pub inline fn calcJDFromJulianCent(t: f64) f64 {
    return t * 36525.0 + 2451545.0;
}

pub inline fn julian_date_from_timestamp(timestamp: f64) f64 {
    return (timestamp / 86400.0) + 2440587.5;
}

pub inline fn timestamp_from_julian_date(julian_date: f64) f64 {
    return (julian_date - 2440587.5) * 86400.0;
}

pub const Timestamp = struct {
    timestamp: f64 = 0.0,
    tzOffset: i32 = 0,

    var ts_tm: ctime.struct_tm = .{};
    var local_tm: ctime.struct_tm = .{};
    var julian_date: f64 = 0.0;
    var julian_century: f64 = 0.0;
    var julian_day_number: i64 = 0;

    const Self = @This();

    pub fn init(timestamp: f64, tzOffset: i32) !Self {
        julian_date = julian_date_from_timestamp(timestamp);
        julian_century = calcTimeJulianCent(julian_date);

        const tst = @as(c_long, @intFromFloat(@round(timestamp)));
        var err = ctime.gmtime_r(&tst, &ts_tm);
        if (err == null) {
            return TimeError.GMTime;
        }
        const tzt: ctime.time_t = tst + tzOffset;
        err = ctime.gmtime_r(&tzt, &local_tm);
        if (err == null) {
            return TimeError.GMTime;
        }

        julian_day_number = @as(i64, @intFromFloat(@round(julian_date + (12.0 - @as(f64, @floatFromInt(ts_tm.tm_hour))) / 24.0 - @as(f64, @floatFromInt(ts_tm.tm_min)) / 1440.0 - @as(f64, @floatFromInt(ts_tm.tm_sec)) / 86400.0)));

        return Timestamp{
            .timestamp = timestamp,
            .tzOffset = tzOffset,
        };
    }

    pub inline fn get_julian_date(_: Self) f64 {
        return julian_date;
    }

    pub inline fn get_julian_century(_: Self) f64 {
        return julian_century;
    }

    pub inline fn get_julian_day_number(_: Self) i64 {
        return julian_day_number;
    }

    pub inline fn get_timestruct_UT(_: Self) ctime.struct_tm {
        return ts_tm;
    }

    pub inline fn get_timestruct_tz(_: Self) ctime.struct_tm {
        return local_tm;
    }
};

pub const SunAngle = enum(f32) {
    Official = 90.833,
    Nautical = 102.0,
    Civil = 96.0,
    Astronomical = 108.0,
};

pub inline fn degToRad(rad: f64) f64 {
    return (180.0 * rad) / zmath.pi;
}

pub inline fn radToDeg(deg: f64) f64 {
    return (zmath.pi * deg) / 180.0;
}

pub inline fn is_leap_year(year: i32) bool {
    return (year % 4 == 0 and year % 100 != 0) || year % 400 == 0;
}

pub fn calcRefraction(elev: f64) f64 {
    if (elev > 85.0) {
        return 0.0;
    }
    const te = @tan(degToRad(elev));
    if (elev > 5.0) {
        return (58.1 / te - 0.07 / (te * te * te) + 0.000086 / (te * te * te * te * te)) / 3600.0;
    }
    if (elev > -0.575) {
        return (1735.0 +
            elev * (-518.2 + elev * (103.4 + elev * (-12.79 + elev * 0.711)))) / 3600.0;
    }
    return (-20.774 / te) / 3600.0;
}

pub inline fn calcGeomMeanLongSun(t: f64) f64 {
    return @mod(280.46646 + t * (36000.76983 + t * 0.0003032), 360.0); //degrees
}

pub inline fn calcGeomMeanAnomalySun(t: f64) f64 {
    return 357.52911 + t * (35999.05029 - 0.0001537 * t); //degrees
}

pub inline fn calcEccentricityEarthOrbit(t: f64) f64 {
    return 0.016708634 - t * (0.000042037 + 0.0000001267 * t); //unitless
}

pub fn calcSunEqOfCenter(t: f64) f64 {
    const mrad = degToRad(calcGeomMeanAnomalySun(t));
    const sinm = @sin(mrad);
    const sin2m = @sin(mrad + mrad);
    const sin3m = @sin(mrad + mrad + mrad);
    return sinm * (1.914602 - t * (0.004817 + 0.000014 * t)) +
        sin2m * (0.019993 - 0.000101 * t) +
        sin3m * 0.000289; // in degrees
}

pub inline fn calcSunTrueLong(t: f64) f64 {
    return calcGeomMeanLongSun(t) + calcSunEqOfCenter(t); // degrees
}

pub inline fn calcSunTrueAnomaly(t: f64) f64 {
    return calcGeomMeanAnomalySun(t) + calcSunEqOfCenter(t); // degrees
}

pub inline fn calcSunRadVector(t: f64) f64 {
    const e = calcEccentricityEarthOrbit(t);
    return (1.000001018 * (1 - e * e)) / (1 + e * @cos(degToRad(calcSunTrueAnomaly(t)))); // AUs
}

pub inline fn calcSunApparentLong(t: f64) f64 {
    return calcSunTrueLong(t) - 0.00569 - 0.00478 * @sin(degToRad(125.04 - 1934.136 * t)); // degrees
}

pub inline fn calcMeanObliquityOfEcliptic(t: f64) f64 {
    return 23.0 + (26.0 + (21.448 - t *
        (46.815 + t * (0.00059 - t * 0.001813))) / 60.0) / 60.0; //degrees
}

pub inline fn calcObliquityCorrection(t: f64) f64 {
    return calcMeanObliquityOfEcliptic(t) + 0.00256 * @cos(degToRad(125.04 - 1934.136 * t)); //degrees
}

pub fn calcSunRtAscension(t: f64) f64 {
    const lambda = calcSunApparentLong(t);
    return radToDeg(zmath.atan2(@cos(degToRad(calcObliquityCorrection(t))) * @sin(degToRad(lambda)), @cos(degToRad(lambda)))); // degrees
}

pub inline fn calcSunDeclination(t: f64) f64 {
    return radToDeg(zmath.asin(@sin(degToRad(calcObliquityCorrection(t))) * @sin(degToRad(calcSunApparentLong(t))))); //degrees
}

pub fn calcEquationOfTime(t: f64) f64 {
    const l0 = degToRad(calcGeomMeanLongSun(t)) * 2.0;
    const m = degToRad(calcGeomMeanAnomalySun(t));
    const e = calcEccentricityEarthOrbit(t);
    const sinm = @sin(m);
    var y = @tan(degToRad(calcObliquityCorrection(t)) / 2.0);
    y *= y;
    return radToDeg(y * @sin(l0) -
        2.0 * e * sinm +
        4.0 * e * y * sinm * @cos(l0) -
        0.5 * y * y * @sin(l0 + l0) -
        1.25 * e * e * @sin(m + m)) * 4.0; // minutes of time
}

pub const Sunriset = struct {
    latitude: f32,
    longitude: f32,
    elevation: f32 = 0.0,
    timestamp: Timestamp,
    sun_angle: SunAngle = .Official,

    const Self = @This();
};

test "Jan_01_2000_12:00:00UTC_Julian_Date" {
    const ts = try Timestamp.init(946728000, 0);
    try std.testing.expect(ts.get_julian_date() == 2451545.0);
}
