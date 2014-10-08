use GTK::Simple;
use Cairo;
use NativeCall;

gtk_simple_use_cairo;

my GTK::Simple::App $app .= new: title => "A totally cool shooter game!";

$app.set_content(
    my $da = GTK::Simple::DrawingArea.new()
);

$app.size_request(800, 600);

constant STARCOUNT = 1000;
constant CHUNKSIZE = STARCOUNT div 4;

constant W = 800;
constant H = 600;

my Int @star_x = (0..W).roll(STARCOUNT);
my Int @star_y = (0..H).roll(STARCOUNT);

my @star_surfaces = do for ^4 -> $chunk {
        my $tgt = Cairo::Image.create(FORMAT_A8, W, 2 * H);
        my $ctx = Cairo::Context.new($tgt);

        $ctx.line_cap = LINE_CAP_ROUND;
        $ctx.rgba(1, 1, 1, 1);
        for ^CHUNKSIZE {
            $ctx.move_to(@star_x[$_ + $chunk * CHUNKSIZE], @star_y[$_ + $chunk * CHUNKSIZE]);
            $ctx.line_to(0, 0, :relative);
            $ctx.move_to(@star_x[$_ + $chunk * CHUNKSIZE], @star_y[$_ + $chunk * CHUNKSIZE] + H);
            $ctx.line_to(0, 0, :relative);
            $ctx.stroke;
        }

        $tgt.reference();
        $ctx.destroy();
        $tgt;
    }

my int $px = W div 2;
my int $py = H * 4 div 5;

$da.events.set(KEY_PRESS_MASK, KEY_RELEASE_MASK);

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

        $widget.queue_draw;

        say "drawn in { nqp::time_n() - $start } s";

        CATCH {
            say $_
        }
    });


$app.run();
