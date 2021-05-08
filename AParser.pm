package AParser;
use strict;
use warnings;
use LWP;
use JSON::XS;

sub new {
    my ($class, $url, $password, %opts) = @_;

    my $self = bless {
        'ua' => LWP::UserAgent->new(timeout => 600),
        'url' => $url,
        'password' => $password,
        'debug' => $opts{'debug'}
    }, $class;
    
    $self->registerAction($_) foreach qw/ping info getProxies/;
    
    $self->registerAction($_, 'taskUid') foreach qw/getTaskState getTaskConf getTaskResultsFile deleteTaskResultsFile/;
    $self->registerAction('getParserPreset', 'parser', 'preset');
    
    $self->registerAction('oneRequest', 'parser', 'preset', 'query', undef); #opts defaults: doLog => 1, rawResults => 0
    $self->registerAction('bulkRequest', 'parser', 'preset', 'threads', 'queries', undef); #opts defaults: doLog => 1, rawResults => 0
    
    $self->registerAction('addTask', 'configPreset', 'preset', 'queriesFrom', 'queries', undef, sub {
        my $request = shift;
        $request->{'data'}->{'queriesFile'} = delete $request->{'data'}->{'queries'} if $request->{'data'}->{'queriesFrom'} ne 'text';
    });
    
    $self->registerAction('changeTaskStatus', 'taskUid', 'toStatus'); #toStatus: starting|pausing|stopping|deleting
    $self->registerAction('moveTask', 'taskUid', 'direction'); #direction: up|down|start|end
    
    return $self;
};

sub doRequest {
    my($self, $request) = @_;
    
    $request->{'password'} = $self->{'password'};
    $request = encode_json $request;
    
    my $pretty = JSON::XS->new->pretty() if $self->{'debug'};
    warn "Request:\n", $pretty->encode(decode_json $request), "\n" if $self->{'debug'};
    
    my $response = $self->{'ua'}->post(
        $self->{'url'},
        'Content-Type' => 'text/plain; charset=UTF-8',
        'Content-Length' => length $request,
        'Content' => $request
    );
    
    if($response->is_success) {
        my $json = eval { decode_json $response->content() };

        if($@ || ref $json ne 'HASH') {
            return undef, 'Response fail: json decode error';
        }
        else {
            warn "Response:\n", $pretty->encode($json), "\n" if $self->{'debug'};
            if($json->{'success'}) {
                return exists $json->{'data'} ? $json->{'data'} : 1;
            }
            else {
                return undef, 'Response fail: ' . ($json->{'msg'} || 'unknow error');
            };
        };
    }
    else {
        return undef, 'Response fail: ' . $response->status_line();
    };
};

sub registerAction {
    my($self, $action, @params) = @_;
    
    my $patchRequest;
    $patchRequest = pop @params if ref $params[-1] eq 'CODE';

    no strict 'refs';

    *{$action} = sub {
        my $self = shift;
        my %opts;
        
        foreach(@params) {
            if(defined $_) {
                $opts{$_} = shift @_;
            }
            else {
                %opts = (%opts, @_);
            };
        };
        
        my $request = {
            'action' => $action,
            scalar keys %opts ? ('data' => \%opts) : ()
        };
        
        $patchRequest->($request) if defined $patchRequest;
        
        return $self->doRequest($request);
    };
    
    use strict 'refs';
};

sub waitForTask {
    my($self, $taskUid, $interval) = @_;
    $interval ||= 5;
    while() {
        my($state, $error) = $self->getTaskState($taskUid);
        if(!defined $state || $state->{'status'} eq 'completed') {
            return $state, $error;
        };
        sleep $interval;
    };
};

1;