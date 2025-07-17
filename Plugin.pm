package Plugins::Twitch::Plugin;

use strict;
use base qw(Slim::Plugin::OPMLBased);

use Slim::Networking::SimpleAsyncHTTP;
use Slim::Utils::Log;
use Slim::Utils::Prefs;
use Slim::Control::Request;
use Slim::Utils::Strings qw(string cstring);

use JSON::XS::VersionOneAndTwo qw(encode_json decode_json);

my $log   = Slim::Utils::Log->addLogCategory({ category => 'Twitch', defaultLevel => 'INFO' });
my $prefs = preferences('plugin.Twitch');

sub initPlugin {
    my ($class, $client) = @_;

    $class->SUPER::initPlugin(
        feed    => \&getFeedItems,
        tag     => 'twitch',
        menu    => 'radios',
        is_app  => 1,
        weight  => 1,
    );

    $log->info("Twitch Audio Stream Plugin initialized.");
}

sub getDisplayName {
    return "PLUGIN_TWITCH";
}

sub getFeedItems {
    my ($client, $callback) = @_;

    my @items = ({
        name => 'Play Twitch Audio Stream',
        type => 'link',
        url  => \&getStreamUrl,
    });

    $callback->(\@items);
}

sub getStreamUrl {
    my ($client, $cb) = @_;

    return unless $client;

    my $channel  = $prefs->get('twitch_channel') || 'sgqfmfunk';
    my $clientId = 'kimne78kx3ncx6brgo4mv6wki5h1ko';

    my $token_req = {
        operationName => 'PlaybackAccessToken_Template',
        variables     => {
            login      => $channel,
            playerType => 'site',
        },
        query => 'query PlaybackAccessToken_Template($login: String!, $playerType: String!) { streamPlaybackAccessToken(channelName: $login, params: { platform: "web", playerBackend: "mediaplayer", playerType: $playerType }) { signature value } }',
    };

    my $token_json = encode_json($token_req);
    my $url        = 'https://gql.twitch.tv/gql';

    my $http = Slim::Networking::SimpleAsyncHTTP->new(
        sub {
            my $json = shift;
            my $data = eval { decode_json($json) };
            unless ($data) {
                $log->warn("Failed to parse Twitch token JSON");
                return;
            }

            my $sig = $data->{data}->{streamPlaybackAccessToken}->{signature};
            my $tok = $data->{data}->{streamPlaybackAccessToken}->{value};

            my $m3u8 = "https://usher.ttvnw.net/api/channel/hls/${channel}.m3u8?sig=${sig}&token=${tok}&allow_audio_only=true";

            my $m3u8_http = Slim::Networking::SimpleAsyncHTTP->new(
                sub {
                    my $body = shift;
                    my ($audio_url) = $body =~ /(https.*audio_only.*\.m3u8)/;

                    unless ($audio_url) {
                        $log->warn("Audio only stream URL not found in M3U8");
                        return;
                    }

                    $client->playingSong->pluginData(wmaMeta => {
                        icon   => "https://static-cdn.jtvnw.net/jtv_user_pictures/7884f1bf-025c-4d89-bd4c-38a28238fc10-profile_image-300x300.png",
                        cover  => "https://static-cdn.jtvnw.net/jtv_user_pictures/7884f1bf-025c-4d89-bd4c-38a28238fc10-profile_image-300x300.png",
                        artist => $channel,
                        title  => "Live Twitch Stream",
                    });

                    Slim::Control::Request::notifyFromArray($client, ['newmetadata']);
                    Slim::Control::Request::executeRequest($client, ['playlist', 'play', $audio_url]);
                },
                sub { $log->warn("Failed to fetch M3U8: $_[0]") }
            );

            $m3u8_http->get($m3u8);
        },
        sub { $log->warn("Failed to get Twitch token: $_[0]") }
    );

    $http->headers({
        'Client-ID'    => $clientId,
        'Content-Type' => 'application/json',
        'User-Agent' => 'Mozilla/5.0 (X11; Linux x86_64) AppleWebKit/537.36 (KHTML, like Gecko) Chrome/138.0.0.0 Safari/537.36'
    });

    $http->post($url, $token_json);
}

1;
