use GTK::Simple;
use Cairo;
use NativeCall;

gtk_simple_use_cairo;

my GTK::Simple::App $app .= new: title => "Draw on me!";

$app.set_content(
    my $da = GTK::Simple::DrawingArea.new()
);

$app.size_request(800, 600);

constant STARCOUNT = 1000;
constant CHUNKSIZE = STARCOUNT div 4;

my Int @star_x = (0..800).roll(STARCOUNT);
my Int @star_y = (0..600).roll(STARCOUNT);

my @star_surfaces = do for ^4 -> $chunk {
        Cairo::RecordingSurface.record(-> $ctx {
            $ctx.rectangle(0, 0, 800, 600);
            $ctx.rgba(0, 0, 0, 0);
            $ctx.fill();
            $ctx.line_cap = LINE_CAP_ROUND;
            $ctx.rgba(my $brightness = 1 - $chunk * 0.2, $brightness, $brightness, 1);
            for ^CHUNKSIZE {
                $ctx.move_to(@star_x[$_ + $chunk * CHUNKSIZE], @star_y[$_ + $chunk * CHUNKSIZE]);
                $ctx.line_to(0, 0, :relative);
                $ctx.stroke;
            }
        }, :content(CONTENT_COLOR_ALPHA))
    }

my int $px = 400;
my int $py = 500;

$da.add_draw_handler(
    -> $widget, $ctx {
        my $start = nqp::time_n();

        my ($w, $h) = 800, 600;
        $ctx.rgba(0, 0, 0, 1);
        $ctx.rectangle(0, 0, $w, $h);
        $ctx.fill();

        my @yoffs  = (nqp::time_n() <<*<< (100, 80, 50, 15)) >>%>> 600;

        for @star_surfaces Z @yoffs -> $surf, $yoffs {
            $ctx.save();
            $ctx.set_source_surface($surf, 0, $yoffs);
            $ctx.paint();
            $ctx.translate(0, -600);
            $ctx.paint();
            $ctx.restore();
        }

        $ctx.translate($px, $py);
        $ctx.scale(0.5, 0.5);
        $ctx.line_width = 8;
        $ctx.rgb(1, 1, 1);

        $ctx.move_to(0, -64);
        $ctx.line_to(32, 32);
        $ctx.curve_to(20, 16, -20, 16, -32, 32);
        $ctx.close_path();
        $ctx.stroke :preserve;
        $ctx.rgb(0.25, 0.25, 0.25);
        $ctx.fill;

        $widget.queue_draw;

        #say "drawn in { nqp::time_n() - $start } s";

        CATCH {
            say $_
        }
    });


$app.run();
