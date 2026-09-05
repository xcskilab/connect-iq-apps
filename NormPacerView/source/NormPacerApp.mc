import Toybox.Application;
import Toybox.Lang;
import Toybox.WatchUi;

class NormPacerApp extends Application.AppBase {
    // Kept so a settings change can reach the view. A data field has exactly
    // one view for its whole life.
    private var mView as NormPacerView?;

    function initialize() {
        AppBase.initialize();
        mView = null;
    }

    // onStart() is called on application start up
    function onStart(state as Dictionary?) as Void {
    }

    // onStop() is called when your application is exiting
    function onStop(state as Dictionary?) as Void {
    }

    //! Return the initial view of your application here
    function getInitialView() as [Views] or [Views, InputDelegates] {
        var view = new NormPacerView();
        mView = view;
        return [view];
    }

    //! Called when the rider changes a setting in the Garmin Connect app or
    //! Garmin Express while the field is running.
    function onSettingsChanged() as Void {
        var view = mView;
        if (view != null) {
            view.onSettingsChanged();
        }
        WatchUi.requestUpdate();
    }
}

function getApp() as NormPacerApp {
    return Application.getApp() as NormPacerApp;
}
