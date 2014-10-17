use GTK::Simple;
use GTK::GDK;
use Cairo;
use NativeCall;

gtk_simple_use_cairo;

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

$app.set_content(
    GTK::Simple::HBox.new(
        my $da = GTK::Simple::DrawingArea.new(),
        GTK::Simple::DrawingArea.new()
    )
);

constant REFRACT_PROB = 30;
constant ENEMY_PROB = 5;

constant STARCOUNT = 1000;
constant CHUNKSIZE = STARCOUNT div 4;

constant W = 800;
constant H = 600;

constant SCALE = (1200 / 800) min (900 / 600);

say W * SCALE;
say H * SCALE;

my $game_draw_handler;

$app.size_request(W * SCALE, H * SCALE);
$da.size_request(W * SCALE, H * SCALE);

my Int @star_x = (0..W).roll(STARCOUNT);
my Int @star_y = (0..H).roll(STARCOUNT);

my @star_surfaces = do for ^4 -> $chunk {
        my $tgt = Cairo::Image.record(
        -> $ctx {
            $ctx.line_cap = LINE_CAP_ROUND;
            $ctx.rgba(1, 1, 1, 1);

            for ^CHUNKSIZE {
                my $star_x = (0..W).pick;
                my $star_y = (0..H).pick;
                $ctx.move_to($star_x, $star_y);
                $ctx.line_to(0, 0, :relative);
                $ctx.move_to($star_x, $star_y + H);
                $ctx.line_to(0, 0, :relative);
                $ctx.stroke;
            }

            $tgt;
        }, W, 2 * H, FORMAT_A8);
    }

my $player = Object.new( :pos(H / 2 + (H * 6 / 7)\i) );

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
my $nextreload = 0;
my @kills;

my $explosion_background = 0;

my $go_t;
$app.g_timeout(1000 / 50).act(
    -> @ ($t, $dt) {

        $explosion_background -= $dt if $explosion_background > 0;

        if $player.lifetime {
            $player.lifetime -= $dt;
            if $player.lifetime < 0 {
                if $game_draw_handler.connected {
                    $game_draw_handler.disconnect();
                    $da.add_draw_handler(&game_over_screen);
                    @kills>>.lifetime = Num;
                    .HP = 0b11 for @kills;
                    $go_t = nqp::time_n();
                }
            }
        } else {
            if %down_keys<K_LEFT> && $player.pos.re > 20 {
                $player.pos -= 512 * $dt;
            }
            if %down_keys<K_RIGHT> && $player.pos.re < W - 20 {
                $player.pos += 512 * $dt;
            }
        }

        if %down_keys<K_SPACE> {
            if $t > $nextreload && !defined $player.lifetime {
                @bullets.push(Object.new(:pos($player.pos), :vel(0 - 768i)));
                $nextreload = $t + 0.1;
            }
        }

        for @bullets, @enemies {
            $_.pos += $dt * $_.vel;
        }
        @bullets .= grep(
            -> $b {
                my $p = $b.pos;
                0 < $b.pos.re < W
                and 0 < $b.pos.im < H
        });

        for @enemies {
            $_.pos += $dt * $_.vel;

            if $_.pos.re < 20 && $_.vel.re < 0 {
                $_.vel = -$_.vel.re + $_.vel.im\i
            }
            if $_.pos.re > W - 20 && $_.vel.re > 0 {
                $_.vel = -$_.vel.re + $_.vel.im\i
            }
            if !defined $_.lifetime && $_.vel.im < 128 {
                $_.vel += ($dt * 100)\i;
                my $polarvel = $_.vel.polar;
                $_.vel = unpolar($polarvel[0] min 128, $polarvel[1]);
            }
            if $_.lifetime {
                $_.lifetime -= $dt;
                $_.vel *= 0.8;
            } else {
                if !defined $player.lifetime {
                    for @bullets -> $b {
                        next unless -20 < $b.pos.re - $_.pos.re < 20;
                        next unless -20 < $b.pos.im - $_.pos.im < 20;

                        my $posdiff   = ($_.pos - $b.pos);
                        my $polardiff = $posdiff.polar;
                        if $polardiff[0] < 30 {
                            if $_.HP == 0 {
                                $_.lifetime = 2e0;
                                $_.vel += $b.vel / 4;
                                $_.vel *= 4;
                                if 100.rand < REFRACT_PROB {
                                    for ^4 {
                                        @bullets.push:
                                            Object.new: :pos($b.pos), :vel(unpolar(768, (2 * pi).rand));
                                    }
                                }
                                @kills.push($_);
                                $explosion_background = 0.9 + 0.1.rand;
                            } elsif $_.HP > 0 && $_.HP <= 0b11 {
                                if $posdiff.re < 0 {
                                    $_.HP +&= +^ 0b01;
                                } else {
                                    $_.HP +&= +^ 0b10;
                                }
                                $_.vel = $posdiff * 3;
                                $_.vel -= 100i if $_.vel.im >= -50;
                            } elsif $_.HP >= 0b11 {
                                $_.HP--;
                            }
                            $b.pos -= 1000i;
                            last;
                        }
                    }
                }

                if ($player.pos - $_.pos).polar[0] < 40 {
                    $player.lifetime //= 3e0;
                }
            }
        }
        @enemies .= grep({ $_.pos.im < H + 30 && (!$_.lifetime || $_.lifetime > 0) });

        if 100.rand < ENEMY_PROB {
            @enemies.push: Enemy.new:
                :pos(1000.rand + 12 - 15i),
                :vel((100.rand - 50) + 128i),
                :HP(3);
        }

        $da.queue_draw;

        CATCH {
            say $_
        }
    });

my @frametimes;

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
        for ^10 {
            my $pic = ($_ * pi * 2) / 10;
            $ctx.line_to(sin($pic) * 1, cos($pic) * 1);
            $ctx.line_to(sin($pic + pi * 2 / 20) * 0.3, cos($pic + pi * 2 / 20) * 0.3);
        }
        $ctx.line_to(0, 1);
        $ctx.operator = OPERATOR_XOR;
        $ctx.fill();

        $ctx.pop_group_to_source();
        $ctx.paint();

        $ctx.restore();

        $ctx.operator = OPERATOR_OVER;
        $ctx.rgb(1, 1, 1);
        $ctx.scale($rad, $rad);
        $ctx.line_width = 1 / $rad;
        $ctx.rotate($ship.lifetime * 0.1);
        $ctx.move_to(0, 1);
        for ^10 {
            my $pic = ($_ * pi * 2) / 10;
            $ctx.line_to(sin($pic) * 1, cos($pic) * 1);
            $ctx.line_to(sin($pic + pi * 2 / 20) * 0.3, cos($pic + pi * 2 / 20) * 0.3);
        }
        $ctx.line_to(0, 1);
        $ctx.stroke();
    } else {
        $ctx.scale(0.3, 0.3);
        $ctx.line_width = 8;
        $ctx.rgb(1, 1, 1);

        $ctx.move_to(0, -64);
        $ctx.line_to(32, 32);
        $ctx.curve_to(20, 16, -20, 16, -32, 32);
        $ctx.close_path();
        $ctx.stroke :preserve;
        $ctx.rgb(0.25, 0.25, 0.25);
        $ctx.fill;
    }
    CATCH {
        say $_
    }
}

sub enemyship($ctx, $ship) {
    if $ship.lifetime {
        $ctx.rgb(($ship.id % 100) / 100, ($ship.id % 75) / 75, ($ship.id % 13) / 13);
        $ctx.rotate($ship.lifetime * ($ship.id % 128 - 64) * 0.01);
        my $rad = ($ship.lifetime ** 4 + 0.001) * 5;
        $ctx.scale($rad, $rad);
        $ctx.line_width = 1 / $rad;
        $ctx.move_to(0, 1);
        for ^10 {
            my $pic = ($_ * pi * 2) / 10;
            $ctx.line_to(sin($pic) * 1, cos($pic) * 1);
            $ctx.line_to(sin($pic + pi * 2 / 20) * 0.3, cos($pic + pi * 2 / 20) * 0.3);
        }
        $ctx.line_to(0, 1);
        $ctx.fill() :preserve;
        $ctx.rgb(1, 0, 0);
        $ctx.stroke();
    } else {
        my $polarvel = $ship.vel.polar;

        $ctx.rotate($polarvel[1] - 0.5 * pi);

        if ($player.lifetime // 2) > 0 {
            $ctx.line_cap = LINE_CAP_ROUND;
            for ^4 {
                $ctx.rgba(0, 0, 1, 0.4.rand + 0.1);
                $ctx.line_width = $_ ** 2;
                $ctx.move_to(0, -13);
                $ctx.line_to(0, -(1 / $_) * 50) :relative;
                $ctx.stroke();
            }
        }

        $ctx.line_width = 1;
        $ctx.rgb(($ship.id % 100) / 100, ($ship.id % 75) / 75, ($ship.id % 13) / 13);
        $ctx.move_to(5, -15);
        $ctx.line_to(-5, -15);
        if $ship.HP >= 0b11 || $ship.HP +& 0b10 {
            $ctx.curve_to(-30, -15, -15, 15, -5, 15);
        }
        $ctx.line_to(-3, -5);
        $ctx.line_to(0, 5);
        $ctx.line_to(3, -5);
        if $ship.HP >= 3 || $ship.HP +& 0b01 {
            $ctx.line_to(5, 15);
            $ctx.curve_to(15, 15, 30, -15, 5, -15);
        }
        $ctx.line_to(5, -15);

        $ctx.line_to(0, -5) :relative;
        $ctx.line_to(-10, 0) :relative;
        $ctx.line_to(0, 5) :relative;

        $ctx.fill() :preserve;
        $ctx.rgb(1, 1, 1);
        $ctx.stroke();
    }
}

sub game_over_screen($widget, $ctx) {
    state $screen_img = Cairo::Image.record(
        -> $ctx {
            $ctx.rectangle(0, 0, W * SCALE, H * SCALE);
            $ctx.rgb(0, 0, 0);
            $ctx.fill();
        }, W * SCALE, H * SCALE);
    $ctx.set_source_surface($screen_img);
    $ctx.paint();
    $ctx.scale(SCALE, SCALE);

    state $edgelength = (@kills + 1).sqrt.ceiling;
    $ctx.scale(my $factor = (H - 100) / ($edgelength * 50), $factor);
    $ctx.translate(50, 50);
    for ^@kills {
        my $kill = @kills[$_];
        next unless defined $kill;
        my $maybe = (nqp::time_n() - $go_t) * 3 - ($kill.id % ($edgelength * 3)) / 3;
        #$maybe min= 1;
        if 1 >= $maybe >= 0 {
            $ctx.save();
            $ctx.translate(50 * ($_ % $edgelength), 50 * ($_ div $edgelength));
            $ctx.scale($maybe, $maybe);
            $ctx.&enemyship($kill);
            $ctx.restore();
        } elsif $maybe > 1 {
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

    CATCH {
        say $_
    }
}

$game_draw_handler = $da.add_draw_handler(
    -> $widget, $ctx {
        my $start = nqp::time_n();

        $ctx.scale(SCALE, SCALE);

        $ctx.rgba(0.2 * $explosion_background ** 4, 0.2 * $explosion_background ** 4, 0.2 * $explosion_background ** 4, 1);
        $ctx.rectangle(0, 0, W, H);
        $ctx.fill();

        my $ft = nqp::time_n();

        my @yoffs  = do (nqp::time_n() * $_) % H - H for (100, 80, 50, 15);

        for ^4 {
            $ctx.save();
            $ctx.rgba(1, 1, 1, 1 - $_ * 0.2);
            $ctx.mask(@star_surfaces[$_], 0, @yoffs[$_]);
            $ctx.fill();
            $ctx.restore();
        }

        $ctx.save();
        $ctx.rgba(0, 0, 1, 0.75);
        $ctx.line_width = 8;

        for @bullets {
            $ctx.move_to($_.pos.re, $_.pos.im);
            $ctx.line_to($_.vel.re * 0.05, $_.vel.im * 0.05) :relative;
        }
        $ctx.stroke();
        $ctx.restore();

        $ctx.save();
        $ctx.rgb(1, 1, 1);
        $ctx.line_width = 3;

        for @bullets {
            $ctx.move_to($_.pos.re, $_.pos.im);
            $ctx.line_to($_.vel.re * 0.03, $_.vel.im * 0.03) :relative;
        }
        $ctx.stroke();
        $ctx.restore();

        for @enemies {
            $ctx.save();
            $ctx.translate($_.pos.re, $_.pos.im);
            $ctx.&enemyship($_);
            $ctx.restore();
        }

        $ctx.save;
        $ctx.translate($player.pos.re, $player.pos.im);
        $ctx.&playership($player);
        $ctx.restore();

        @frametimes.push: nqp::time_n() - $start;

        CATCH {
            say $_
        }
    });

$app.run();

say "analysis of frame times incoming";
@frametimes .= sort;

say "{+@frametimes} frames rendered";
my @timings = (@frametimes[* div 50], @frametimes[* div 4], @frametimes[* div 2], @frametimes[* * 3 div 4], @frametimes[* - * div 100]);
say @timings;

say "frames per second:";
say 1 X/ @timings;
