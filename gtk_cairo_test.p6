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

my GTK::Simple::App $app .= new: title => "A totally cool shooter game!";

$app.set_content(
    GTK::Simple::HBox.new(
        my $da = GTK::Simple::DrawingArea.new(),
        GTK::Simple::DrawingArea.new()
    )
);

constant REFRACT_PROB = 25;
constant ENEMY_PROB = 20;

constant STARCOUNT = 1000;
constant CHUNKSIZE = STARCOUNT div 4;

constant W = 1024;
constant H = 786;

constant SCALE = (1920 / 1024) min (1080 / 786);

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

my $go_t;
$app.g_timeout(1000 / 50).act(
    -> @ ($t, $dt) {

        if $player.lifetime {
            $player.lifetime -= $dt;
            if $player.lifetime < 0 {
                if $game_draw_handler.connected {
                    $game_draw_handler.disconnect();
                    $da.add_draw_handler(&game_over_screen);
                    @kills>>.lifetime = Num;
                    $go_t = nqp::time_n();
                }
            }
        } else {
            if %down_keys<K_LEFT> {
                $player.pos -= 512 * $dt;
            }
            if %down_keys<K_RIGHT> {
                $player.pos += 512 * $dt;
            }
        }

        if %down_keys<K_SPACE> {
            if $t > $nextreload && !defined $player.lifetime {
                @bullets.push(Object.new(:pos($player.pos), :vel(0 - 768i)));
                $nextreload = $t + 0.3;
            }
        }

        for @bullets, @enemies {
            $_.pos += $dt * $_.vel;
        }
        while @bullets
            and (@bullets[0].pos.im < 0 or @bullets[0].pos.im > 800
                or @bullets[0].pos.re < 0 or @bullets[0].pos.re > 1024) {
            @bullets.shift
        }

        for @enemies {
            $_.pos += $dt * $_.vel;
            if $_.lifetime {
                $_.lifetime -= $dt;
                $_.vel *= 0.8;
            } else {
                for @bullets -> $b {
                    if ($_.pos - $b.pos).polar[0] < 30 {
                        $_.lifetime = 2e0;
                        $_.vel += $b.vel / 4;
                        $_.vel *= 4;
                        if 100.rand < REFRACT_PROB {
                            for ^4 {
                                @bullets.push:
                                    Object.new: :pos($b.pos), :vel(unpolar(768, (2 * pi).rand));
                            }
                        }
                        $b.pos -= 1000i;
                        @kills.push($_);
                        last;
                    }
                }
                if (1024.rand > 1000) {
                    $_.vel = ((100.rand - 50) + 128i);
                }

                if ($player.pos - $_.pos).polar[0] < 40 {
                    $player.lifetime //= 3e0;
                }
            }
        }
        @enemies .= grep({ $_.pos.im < 790 && (!$_.lifetime || $_.lifetime > 0) });

        if 100.rand < ENEMY_PROB {
            @enemies.push: Object.new:
                :pos(1000.rand + 12 - 15i),
                :vel((100.rand - 50) + 128i);
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

        $ctx.rectangle(-$ship.pos.im * 4, -$ship.pos.re * 4, 1024 * 4, 786 * 4);
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
    $ctx.rgb(($ship.id % 100) / 100, ($ship.id % 75) / 75, ($ship.id % 13) / 13);

    if $ship.lifetime {
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

        $ctx.fill() :preserve;
        $ctx.rgb(1, 1, 1);
        $ctx.stroke();
    }
}

sub game_over_screen($widget, $ctx) {
    $ctx.scale(SCALE, SCALE);
    $ctx.rgb(0.1, 0.1, 0.1);
    $ctx.rectangle(0, 0, 1024, 786);
    $ctx.fill();

    my $edgelength = (@kills + 1).sqrt.ceiling;
    $ctx.scale(700 / ($edgelength * 50), 700 / ($edgelength * 50));
    $ctx.translate(50, 50);
    for ^@kills {
        my $kill = @kills[$_];
        my $maybe = (nqp::time_n() - $go_t) * 3 - ($kill.id % ($edgelength * 3)) / 3;
        $maybe min= 1;
        if $maybe >= 0 and $maybe <= 1 {
            $ctx.save();
            $ctx.translate(50 * ($_ % $edgelength), 50 * ($_ div $edgelength));
            $ctx.scale($maybe, $maybe);
            $ctx.&enemyship($kill);
            $ctx.restore();
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

        $ctx.rgba(0, 0, 0, 1);
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
