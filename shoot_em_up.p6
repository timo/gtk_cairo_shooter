use GTK::Simple::App;
use GTK::Simple::DrawingArea;
use GTK::Simple::HBox;
use Cairo;
use NativeCall;

use nqp;

gtk_simple_use_cairo;

use GTK::Simple::NativeLib;

our class GdkWindow is repr('CPointer') { }

enum EVENT_MASK is export (
  EXPOSURE_MASK => 2,
  POINTER_MOTION_MASK => 4,
  POINTER_MOTION_HINT_MASK => 8,
  BUTTON_MOTION_MASK => 16,
  BUTTON1_MOTION_MASK => 32,
  BUTTON2_MOTION_MASK => 64,
  BUTTON3_MOTION_MASK => 128,
  BUTTON_PRESS_MASK => 256,
  BUTTON_RELEASE_MASK => 512,
  KEY_PRESS_MASK => 1024,
  KEY_RELEASE_MASK => 2048,
  ENTER_NOTIFY_MASK => 4096,
  LEAVE_NOTIFY_MASK => 8192,
  FOCUS_CHANGE_MASK => 16384,
  STRUCTURE_MASK => 32768,
  PROPERTY_CHANGE_MASK => 65536,
  VISIBILITY_NOTIFY_MASK => 131072,
  PROXIMITY_IN_MASK => 262144,
  PROXIMITY_OUT_MASK => 524288,
  SUBSTRUCTURE_MASK => 1048576,
  SCROLL_MASK => 2097152,
  ALL_EVENTS_MASK => 4194302,
);

constant carrayuint16 := CArray[uint16];

sub gtk_widget_get_window(OpaquePointer $window)
    returns GdkWindow
    is native(&gtk-lib)
    is export
    {*}

sub gdk_window_get_events(GdkWindow $window)
    returns int32
    is native(&gdk-lib)
    is export
    {*}

sub gdk_window_set_events(GdkWindow $window, int32 $eventmask)
    is native(&gdk-lib)
    is export
    {*}

# GdkEvent datastructure access {{{

our class GdkEvent is repr('CPointer') is export { ... }

sub gdk_event_get_keycode(GdkEvent $event, carrayuint16 $keycode)
    is native(&gdk-lib)
    {*}

sub gdk_event_get_keyval(GdkEvent $event, carrayuint16 $keycode)
    is native(&gdk-lib)
    {*}

our class GdkEvent is export {
    method keycode {
        my carrayuint16 $tgt .= new;
        $tgt[0] = 0;
        gdk_event_get_keycode(self, $tgt);
        $tgt[0]
    }

    method keyval {
        my carrayuint16 $tgt .= new;
        $tgt[0] = 0;
        gdk_event_get_keyval(self, $tgt);
        $tgt[0]
    }
}

class Object is rw {
    has Complex $.pos;
    has Complex $.vel;
    has Int $.id = (4096.rand).Int;
    has Num $.lifetime;
}

class Enemy is Object is rw {
    has Int $.HP;
}

my GTK::Simple::App $app .= new: title => "A totally cool shooter game!";

$app.set-content(
    GTK::Simple::HBox.new(
        my $da = GTK::Simple::DrawingArea.new(),
        GTK::Simple::DrawingArea.new()
    )
);

constant REFRACT_PROB = 30;
constant ENEMY_PROB = 5;

constant PLAYER_RELOAD_TIME = 0.1;

constant STARCOUNT = 1000;
constant CHUNKSIZE = STARCOUNT div 4;

# Real window size
constant SCREEN_W = 1200;
constant SCREEN_H = 900;

# normalized, "fake" window size
constant W = 800;
constant H = 600;

constant SCALE = (SCREEN_W / W) min (SCREEN_H / H);

constant LETTERBOX_LEFT = (SCREEN_W - W * SCALE) / 2;
constant LETTERBOX_TOP  = (SCREEN_H - H * SCALE) / 2;

my $game_draw_handler;

$app.size_request(SCREEN_W, SCREEN_H);
 $da.size_request(SCREEN_W, SCREEN_H);

my @star_surfaces = do for ^4 -> $chunk {
        my $tgt = Cairo::Image.record(
        -> $ctx {
            $ctx.line_cap = Cairo::LINE_CAP_ROUND;
            $ctx.rgb(my $val = 1 - $chunk * 0.2, $val, $val);

            for ^CHUNKSIZE {
                my $star_x = SCREEN_W.rand.Int;
                my $star_y = SCREEN_H.rand.Int;
                $ctx.move_to($star_x, $star_y);
                $ctx.line_to(0, 0, :relative);
                $ctx.move_to($star_x, $star_y + SCREEN_H);
                $ctx.line_to(0, 0, :relative);
            }
            $ctx.stroke;

            $tgt;
        }, SCREEN_W, 2 * SCREEN_H, Cairo::FORMAT_RGB24);
    }

my $player = Object.new( :pos(H / 2 + (H * 6 / 7)\i), :vel(10i) );

$app.events.set(KEY_PRESS_MASK, KEY_RELEASE_MASK);

enum GAME_KEYS (
    K_UP    => 111,
    K_DOWN  => 116,
    K_LEFT  => 113,
    K_RIGHT => 114,
    K_ONE   => 38,
    K_TWO   => 39,
    K_THREE => 40,
    K_SPACE => 65,
);

my %down_keys;

$app.signal_supply("key-press-event").act(
    -> @ ($widget, $raw_event) {
        my $event = nqp::box_i($raw_event.Int, GdkEvent);

        if GAME_KEYS($event.keycode) -> $comm {
            %down_keys{$comm} = 1;
        } else {
            say "new keycode found: $event.keycode()";
        }

        CATCH {
            say $_
        }
    });

$app.signal_supply("key-release-event").act(
    -> @ ($widget, $raw_event) {
        my $event = nqp::box_i($raw_event.Int, GdkEvent);

        if GAME_KEYS($event.keycode) -> $comm {
            %down_keys{$comm} = 0;
        }

        CATCH {
            say $_
        }
    });

my @bullets;
my @enemies;
my @shieldbounces;
my @kills;
my $nextreload = 0;
my $shootside = -1;

my $explosion_background = 0;

my $go_t;
my $framestart;
my @calctimes;
$app.g_timeout(1000 / 50).act(
    -> @ ($t, $dt) {
        $framestart = nqp::time_n();
        $explosion_background -= $dt if $explosion_background > 0;

        if ($player.lifetime // 0) > 0 {
            $player.lifetime -= $dt;
            if $player.lifetime < 0 {
                if $game_draw_handler.connected {
                    $game_draw_handler.disconnect();
                    $da.add_draw_handler(&game_over_screen);
                    @kills.map({ .lifetime = Num });
                    .HP = 0 for @kills;
                    $go_t = nqp::time_n();
                }
            }
        } else {
            if %down_keys<K_LEFT> && $player.pos.re > 20 {
                $player.pos -= 400 * $dt;
            }
            if %down_keys<K_RIGHT> && $player.pos.re < W - 20 {
                $player.pos += 400 * $dt;
            }
            if %down_keys<K_UP> && $player.pos.im > 20 {
                $player.pos -= 400i * $dt;
            }
            if %down_keys<K_DOWN> && $player.pos.im < H - 20 {
                $player.pos += 400i * $dt;
            }
        }

        if %down_keys<K_SPACE> {
            if $t > $nextreload && !defined $player.lifetime {
                @bullets.push: Object.new:
                        :pos($player.pos + ($shootside *= -1) * 15 + 15i),
                        :vel(($shootside * -1) * 25 - 768i),
                        :lifetime(4e0);
                $nextreload = $t + PLAYER_RELOAD_TIME;
            }
        }

        for @bullets {
            $_.pos += $dt * $_.vel;
            $_.lifetime -= $dt;
        }
        for  @shieldbounces {
            $_.pos += $dt * $_.vel;
            $_.lifetime -= $dt if defined $_.lifetime;
        }
        @bullets .= grep(
            -> $b {
                my $p = $b.pos;
                $b.lifetime > 0
                and -50 < $p.re < W + 50
                and -50 < $p.im < H + 50
        });

        for @enemies {
            my $vel := $_.vel;
            my $pos := $_.pos;
            if $pos.re < 15 && $vel.re < 0 {
                $vel = -$vel.re + $vel.im\i
            }
            if $pos.re > W - 15 && $vel.re > 0 {
                $vel = -$vel.re + $vel.im\i
            }
            if !defined $_.lifetime && $vel.im < 182 {
                $vel += ($dt * 100)\i;
                my $polarvel = $vel.polar;
                $vel = unpolar($polarvel[0] min 182, $polarvel[1]);
            }

            $pos += $dt * $vel;

            if $_.lifetime {
                $_.lifetime -= $dt;
                $vel *= 0.8;
            } else {
                if !defined $player.lifetime {
                    for @bullets -> $b {
                        next unless -20 < $b.pos.re - $pos.re < 20;
                        next unless -20 < $b.pos.im - $pos.im < 20;

                        my $posdiff   = ($pos - $b.pos);
                        my $distance  = $posdiff.abs;
                        if $distance < 35 {
                            if $_.HP <= 0 {
                                $_.lifetime = 2e0;
                                if 100.rand < REFRACT_PROB {
                                    for ^4 {
                                        @bullets.push:
                                            Object.new: :pos($b.pos),
                                                        :vel(unpolar(768, (6 * π).rand.Int / 3)),
                                                        :lifetime(3e0);
                                    }
                                }
                                $vel += $b.vel / 4;
                                $vel *= 4;
                                @kills.push($_);
                                $explosion_background = 0.9 + 0.1.rand;
                            } elsif $_.HP > 0 {
                                next if $_.HP <= 2 && $distance >= 25;
                                $_.HP--;
                                my $bumpdiff = unpolar(1, ($posdiff - 30i).polar[1]);
                                #$vel *= 0.7;
                                $vel += $posdiff * 10;
                                if $_.HP >= 2 {
                                    @shieldbounces.push:
                                        Object.new: :$pos,
                                                    :$vel,
                                                    :lifetime(0.25e0);
                                }
                            }
                            $b.pos -= 1000i;
                            last;
                        }
                    }
                }

                if ($player.pos - $_.pos).abs < 35 {
                    $player.lifetime //= 3e0;
                    $explosion_background = 1e0;
                }
            }
        }
        @enemies .= grep({ $_.pos.im < H + 30 && (($_.lifetime // 1) > 0) });
        @shieldbounces.shift while @shieldbounces and @shieldbounces[0].lifetime <= 0;

        if 100.rand < ENEMY_PROB && @enemies < 100 {
            @enemies.push: Enemy.new:
                :pos((W - 24).rand + 12 - 15i),
                :vel((100.rand - 50) + 182i),
                :HP(3);
        }

        $da.queue_draw;

        @calctimes.push: nqp::time_n() - $framestart;

        CATCH {
            say $_
        }
    });

my @frametimes;
my @gctimes;

sub playership($ctx, $ship) {
    if $ship.lifetime {
        $ctx.save();
        $ctx.push_group();

        $ctx.rectangle(-$ship.pos.re * 4, -$ship.pos.im * 4, W * 4, H * 4);
        $ctx.rgb(0, 0, 0);
        $ctx.fill();

        $ctx.rgb(1, 1, 1);
        $ctx.rotate($ship.lifetime * 0.1);
        my $rad = ($ship.lifetime ** 4 + 0.001) * 40;
        $ctx.scale($rad, $rad);
        $ctx.line_width = 1 / $rad;
        $ctx.move_to(0, 1);
        for ^5 {
            my $pic = ($_ * π * 2) / 5;
            $ctx.line_to(sin($pic) * 1, cos($pic) * 1);
            $ctx.line_to(sin($pic + π * 2 / 20) * 0.3, cos($pic + π * 2 / 20) * 0.3);
        }
        $ctx.line_to(0, 1);
        $ctx.operator = Cairo::OPERATOR_XOR;
        $ctx.fill();

        $ctx.pop_group_to_source();
        $ctx.paint();

        $ctx.restore();

        $ctx.operator = Cairo::OPERATOR_OVER;
        $ctx.rgb(1, 1, 1);
        $ctx.scale($rad, $rad);
        $ctx.line_width = 1 / $rad;
        $ctx.rotate($ship.lifetime * 0.1);
        $ctx.move_to(0, 1);
        for ^5 {
            my $pic = ($_ * π * 2) / 5;
            $ctx.line_to(sin($pic) * 1, cos($pic) * 1);
            $ctx.line_to(sin($pic + π * 2 / 20) * 0.3, cos($pic + π * 2 / 20) * 0.3);
        }
        $ctx.line_to(0, 1);
        $ctx.stroke();
    } else {
        given $ctx {
            my $polarvel = $ship.vel.polar;
            .rotate($polarvel[1] - 0.5 * π);
            .scale(0.5, 0.5);
            .line_width = 4;
            .rgb(1, 1, 1);

            .memoize_path(state $playerpath,
            {
                .move_to(-1, -29);
                .line_to(0, -8) :relative;
                .line_to(2, 0) :relative;
                .line_to(0, 8) :relative;
                .close_path();

                .move_to(5, -30);
                for ( -10, 0,  -5, 5,  -5, 20,  5, 5,  -10, 10,  -15, -5,
                      0, -20,  -2, 0,   0, 35,  22, 5,  0, -5,  30, 0,  0, 5,  22, -5,
                      0, -35,  -2, 0,  0, 20,  -15, 5,  -10, -10,  5, -5,  -5, -20) -> $x, $y {
                    .line_to($x, $y) :relative;
                }
                .close_path();
                $playerpath = .copy_path();
            });

            .stroke() :preserve;
            .rgb(0.75, 0.75, 0.75);
            .fill();

            .rgb(0.5, 0.5, 0.5);

            .move_to(6, -5);
            .line_to(-12, 0) :relative;
            .line_to(-1, -6) :relative;
            .line_to(3, -10) :relative;
            .line_to(9, 0) :relative;
            .line_to(3, 10) :relative;
            .close_path();

            .stroke() :preserve;
            .rgb(0.2, 0.2, 0.2);
            .fill();
        }
    }
    CATCH {
        say $_
    }
}

my %damagepatterns;
sub enemyship($ctx, $ship) {
    if $ship.lifetime {
        $ctx.rgb(($ship.id % 100) / 100, ($ship.id % 75) / 75, ($ship.id % 13) / 13);
        $ctx.rotate($ship.lifetime * ($ship.id % 128 - 64) * 0.1);
        my $rad = ($ship.lifetime ** 4 + 0.001) * 5;
        $ctx.scale($rad, $rad);
        $ctx.line_width = 1 / $rad;
        $ctx.move_to(0, 1);
        for ^5 {
            my $pic = ($_ * π * 2) / 5;
            $ctx.line_to(sin($pic) * 1, cos($pic) * 1);
            $ctx.line_to(sin($pic + π * 2 / 20) * 0.3, cos($pic + π * 2 / 20) * 0.3);
        }
        $ctx.line_to(0, 1);
        $ctx.fill() :preserve;
        $ctx.rgb(1, 0, 0);
        $ctx.stroke();
    } else {
        my $polarvel = $ship.vel.polar;
        my $damagemask;

        $ctx.rotate($polarvel[1] - 0.5 * π);
        $ctx.scale(0.8, 0.8);

        if ($player.lifetime // 2) > 0 {
            #$ctx.line_cap = Cairo::LINE_CAP_ROUND;
            for 1..3 {
                $ctx.rgba(0, 0, 1, 0.4.rand + 0.1);
                $ctx.line_width = $_ * $_;
                $ctx.move_to(0, -13);
                $ctx.line_to(0, -13 -(1 / $_) * 50);
                $ctx.stroke();
            }
        }
        #if $ship.HP < 2 {
            #$ctx.push_group();
            #$ctx.rgb(1, 1, 1);
            #$ctx.rectangle(-20, -20, 40, 40);
            #$ctx.fill();
            #$ctx.rgb(0, 0, 0);
            #$ctx.memoize_path((%damagepatterns){$ship.id % 256}{$ship.HP},
            # {
                #for ^(1 max (2 - $ship.HP)) {
                    #my $dir = (($ship.id + $_ * 1311) % 98) / 49 * π;
                    #my $w = 0.3 + ($ship.id % 53) / 97;
                    #my $a = unpolar(40, $dir - $w);
                    #my $b = unpolar(40, $dir + $w);
                    #$ctx.move_to($a.re * 0.05, $a.im * 0.05);
                    #$ctx.line_to($a.re, $a.im);
                    #$ctx.line_to($b.re, $b.im);
                    #$ctx.line_to($b.re * 0.05, $b.im * 0.05);
                    #$ctx.close_path();
                #}
            #}) :flat;
            #$ctx.operator = Cairo::OPERATOR_XOR;
            #$ctx.fill();
            #$ctx.operator = Cairo::OPERATOR_OVER;
            #$damagemask = $ctx.pop_group();
        #}

        #if $damagemask {
            #$ctx.push_group();
        #}

        $ctx.line_width = 1;
        $ctx.rgb(((my int $id = $ship.id) % 100) / 100, ($id % 75) / 75, ($id % 13) / 13);

        $ctx.memoize_path(state $enemypath,
        {
            $ctx.move_to(5, -15);
            $ctx.line_to(-5, -15);
            $ctx.curve_to(-30, -15, -15, 15, -5, 15);
            $ctx.line_to(-3, -5);
            $ctx.line_to(0, 5);
            $ctx.line_to(3, -5);
            $ctx.line_to(5, 15);
            $ctx.curve_to(15, 15, 30, -15, 5, -15);
            $ctx.line_to(5, -15);

            $ctx.line_to(0, -5) :relative;
            $ctx.line_to(-10, 0) :relative;
            $ctx.line_to(0, 5) :relative;

            $enemypath = $ctx.copy_path() :flat;
        });

        $ctx.fill() :preserve;
        $ctx.rgb(1, 1, 1);
        $ctx.stroke();

        #if $damagemask {
            #$ctx.pop_group_to_source();
            #$ctx.mask($damagemask);
            #$damagemask.destroy();
        #}
    }
}

sub shieldbounce($ctx, $bounce) {
    my $polarvel = $bounce.vel.polar;

    $ctx.line_width = 5;
    $ctx.rgba(0, 0, 0.75, 4 * $bounce.lifetime);
    $ctx.arc(0, 0, 30 / ($bounce.lifetime * 2 + 0.75) , 0, 2 * π);
    $ctx.stroke() :preserve;
    $ctx.rgba(0, 0, 0.75, $bounce.lifetime);
    $ctx.fill();
}

sub game_over_screen($widget, $ctx) {
    state $screen_img = Cairo::Image.record(
        -> $ctx {
            $ctx.rectangle(0, 0, W * SCALE, H * SCALE);
            $ctx.rgb(0, 0, 0);
            $ctx.fill();
        }, W * SCALE, H * SCALE);
    $ctx.save();
    $ctx.translate(LETTERBOX_LEFT, LETTERBOX_TOP);
    $ctx.set_source_surface($screen_img);
    $ctx.paint();
    $ctx.scale(SCALE, SCALE);

    state $edgelength = (@kills + 1).sqrt.ceiling;
    $ctx.scale(state $factor = (H - 100) / ($edgelength * 50), $factor);
    $ctx.translate(50, 50);
    for ^@kills {
        my $kill = @kills[$_];
        next unless defined $kill;
        my $maybe = (nqp::time_n() - $go_t) * 3 - ($kill.id % ($edgelength * 3)) / 3;
        $maybe min= 1;
        if $maybe >= 0 {
            $ctx.save();
            $ctx.translate(50 * ($_ % $edgelength), 50 * ($_ div $edgelength));
            $ctx.scale($maybe, $maybe);
            $ctx.&enemyship($kill);
            $ctx.restore();
            if $maybe > 1 {
                $screen_img.record(
                    -> $ctx {
                        $ctx.scale(SCALE, SCALE);
                        $ctx.scale($factor, $factor);
                        $ctx.translate(50, 50);
                        $ctx.translate(50 * ($_ % $edgelength), 50 * ($_ div $edgelength));
                        $ctx.&enemyship($kill);
                    });
                @kills[$_] = Any;
            }
        }
    }

    $ctx.restore();
    $ctx.rgb(0, 0, 0);
    if (LETTERBOX_TOP) {
        $ctx.rectangle(0, 0, SCREEN_W, LETTERBOX_TOP);
        $ctx.rectangle(0, SCREEN_H - LETTERBOX_TOP, SCREEN_W, LETTERBOX_TOP);
    } elsif (LETTERBOX_LEFT) {
        $ctx.rectangle(0, 0, LETTERBOX_LEFT, SCREEN_H);
        $ctx.rectangle(SCREEN_W - LETTERBOX_LEFT, 0, LETTERBOX_LEFT, SCREEN_H);
    }
    $ctx.fill();

    @frametimes.push: nqp::time_n() - $framestart;

    CATCH {
        say $_
    }
}

$game_draw_handler = $da.add_draw_handler(
    -> $widget, $ctx {
        my $render_start_time = nqp::time_n();
        $ctx.antialias = Cairo::ANTIALIAS_FAST;
        $ctx.save();
        $ctx.translate(LETTERBOX_LEFT, LETTERBOX_TOP);
        $ctx.scale(SCALE, SCALE);

        $ctx.rgb(0.4 * $explosion_background ** 4, 0.3 * $explosion_background ** 4, 0.2 * $explosion_background ** 4);
        $ctx.rectangle(0, 0, W, H);
        $ctx.fill();

        my $ft = nqp::time_n();

        #my @yoffs  = do (nqp::time_n() * $_) % H - H for (100, 80, 50, 15);
        my @yoffs  = (nqp::time_n() * 100) % SCREEN_H - SCREEN_H,
                     (nqp::time_n() *  80) % SCREEN_H - SCREEN_H,
                     (nqp::time_n() *  50) % SCREEN_H - SCREEN_H,
                     (nqp::time_n() *  15) % SCREEN_H - SCREEN_H;

        $ctx.save();
        $ctx.operator = Cairo::OPERATOR_ADD;
        $ctx.scale(1 / SCALE, 1 / SCALE);
        for ^4 {
            #$ctx.rgba(1, 1, 1, 1 - $_ * 0.2);
            $ctx.set_source_surface(@star_surfaces[$_], 0, @yoffs[$_]);
            $ctx.paint();
        }
        $ctx.operator = Cairo::OPERATOR_OVER;
        $ctx.restore();

        $ctx.save();
        $ctx.line_width = 8;

        for @bullets {
            $ctx.rgba(0, 0, 1, $_.lifetime min 0.75);
            $ctx.move_to($_.pos.re, $_.pos.im);
            $ctx.line_to($_.vel.re * 0.02, $_.vel.im * 0.02) :relative;
            $ctx.stroke();
        }
        $ctx.line_width = 3;

        for @bullets {
            my $vel := $_.vel;
            $ctx.rgba(1, 1, 1, $_.lifetime min 1);
            $ctx.move_to($_.pos.re, $_.pos.im);
            $ctx.move_to($vel.re * 0.005, $vel.im * 0.005) :relative;
            $ctx.line_to($vel.re * 0.015, $vel.im * 0.015) :relative;
            $ctx.stroke();
        }
        $ctx.restore();

        for @enemies {
            my $pos := $_.pos;
            $ctx.save();
            $ctx.translate($pos.re, $pos.im);
            $ctx.&enemyship($_);
            $ctx.restore();
        }
        for @shieldbounces {
            my $pos := $_.pos;
            $ctx.save();
            $ctx.translate($pos.re, $pos.im);
            $ctx.&shieldbounce($_);
            $ctx.restore();
        }

        $ctx.save;
        $ctx.translate($player.pos.re, $player.pos.im);
        $ctx.&playership($player);
        $ctx.restore();

        $ctx.restore();
        $ctx.rgb(0, 0, 0);
        if (LETTERBOX_TOP) {
            $ctx.rectangle(0, 0, SCREEN_W, LETTERBOX_TOP);
            $ctx.rectangle(0, SCREEN_H - LETTERBOX_TOP, SCREEN_W, LETTERBOX_TOP);
            $ctx.fill();
        } elsif (LETTERBOX_LEFT) {
            $ctx.rectangle(0, 0, LETTERBOX_LEFT, SCREEN_H);
            $ctx.rectangle(SCREEN_W - LETTERBOX_LEFT, 0, LETTERBOX_LEFT, SCREEN_H);
            $ctx.fill();
        }

        #$ctx.line_width = 1;
        #$ctx.rgb(1, 0, 0);
        #$ctx.move_to(10, 10);
        #$ctx.line_to(10 + @enemies * 5, 10);
        #$ctx.stroke;
        #$ctx.rgb(0, 1, 0);
        #$ctx.move_to(10, 20);
        #$ctx.line_to(10 + @shieldbounces * 5, 20);
        #$ctx.stroke;
        #$ctx.rgb(0, 0, 1);
        #$ctx.move_to(10, 30);
        #$ctx.line_to(10 + @bullets * 5, 30);
        #$ctx.stroke;

        #if @frametimes > 50 {
            #$ctx.rgb(1, 1, 1);
            #for 1..50 {
                #my int $pos = @frametimes - $_;
                #$ctx.move_to(10, 40 + $_ * 3);
                #$ctx.line_to(10 + 1 / (@frametimes[$pos]), 40 + $_ * 3);
            #}
            #$ctx.stroke;
        #}

        @frametimes.push: nqp::time_n() - $render_start_time;

        if 2.rand < 1 {
            my $gcstart = nqp::time_n();
            nqp::force_gc();

            @gctimes.push: nqp::time_n() - $gcstart;
        }

        CATCH {
            say $_
        }
    });

$app.run();

say "analysis of frame times incoming";
for $@calctimes, $@frametimes, $(@frametimes Z+ @calctimes), $@gctimes -> @times is copy {
    say "----";
    say <<"calculation times" "rendering times" "complete times" "GC times">>[(state $)++];
    @times .= sort;

    my @timings = (@times[* div 50], @times[* div 4], @times[* div 2], @times[* * 3 div 4], @times[* - * div 100]);

    say "frames per second:";
    say (1 X/ @timings).fmt("%3.4f");
    say "timings:";
    say (     @timings).fmt("%3.4f");
    say "";
}

"frame_rates.txt".IO.spurt: (1 X/ @frametimes).fmt("%3.2f\n")
