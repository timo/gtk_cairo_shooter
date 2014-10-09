use GTK::Simple;
use GTK::GDK;
use Cairo;
use NativeCall;

gtk_simple_use_cairo;

my GTK::Simple::App $app .= new: title => "A totally cool shooter game!";

$app.set_content(
    my $da = GTK::Simple::DrawingArea.new()
);

constant STARCOUNT = 1000;
constant CHUNKSIZE = STARCOUNT div 4;

constant W = 1024;
constant H = 786;

$app.size_request(W, H);

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

my num $px = (W / 2).Num;
my num $py = (H * 6 / 7).Num;

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

class Bullet is rw {
    has Complex $.pos;
    has Complex $.vel;
}

my @bullets;
my $nextreload = 0;

$app.g_timeout(1000 / 50).act(
    -> @ ($t, $dt) {

        if %down_keys<K_LEFT> {
            $px = $px - 256 * $dt;
        }
        if %down_keys<K_RIGHT> {
            $px = $px + 256 * $dt;
        }

        if %down_keys<K_SPACE> {
            if $t > $nextreload {
                @bullets.push(Bullet.new(:pos($px + $py\i), :vel(0 - 768i)));
                $nextreload = $t + 0.3;
            }
        }

        for @bullets {
            $_.pos += $dt * $_.vel;
        }
        while @bullets and @bullets[0].pos.im < 0 {
            @bullets.shift
        }

        $da.queue_draw;

        CATCH {
            say $_
        }
    });

my @frametimes;

$da.add_draw_handler(
    -> $widget, $ctx {
        my $start = nqp::time_n();

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
            $ctx.line_to(0, -16) :relative;
        }
        $ctx.stroke();
        $ctx.restore();

        $ctx.save;
        $ctx.translate($px, $py);
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
