import {run} from '@cycle/xstream-run';
import {makeDOMDriver, div, pre} from '@cycle/dom';
import {makeHTTPDriver} from '@cycle/http';
import xs from 'xstream';

function debug (v) {
  return pre(JSON.stringify(v, null, 2));
}

function main ({DOM, HTTP}) {
  const activities$ = HTTP
    .select('activities')
    .flatten()
    .map(response => response.body)
    .startWith({});

  const requestActivities$ = xs
    .of({
      url: '/activities',
      category: 'activities'
    });

  return {
    DOM: activities$.map(debug),
    HTTP: requestActivities$
  };
}

const drivers = {
  DOM: makeDOMDriver('.app'),
  HTTP: makeHTTPDriver()
};

export default function () {
  run(main, drivers);
}
