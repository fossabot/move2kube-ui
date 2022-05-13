/*
Copyright IBM Corporation 2021

Licensed under the Apache License, Version 2.0 (the "License");
you may not use this file except in compliance with the License.
You may obtain a copy of the License at

  http://www.apache.org/licenses/LICENSE-2.0

Unless required by applicable law or agreed to in writing, software
distributed under the License is distributed on an "AS IS" BASIS,
WITHOUT WARRANTIES OR CONDITIONS OF ANY KIND, either express or implied.
See the License for the specific language governing permissions and
limitations under the License.
*/

import React, { useContext } from 'react';
import { Hints } from '@app/qa/Hints';
import { QAContext } from '@app/qa/QAContext';
import { IQAComponentProps } from '@app/qa/QAWizard';
import { WizardContext } from '@patternfly/react-core';
import { TextContent, TextInput } from '@patternfly/react-core';

function Input(props: IQAComponentProps): JSX.Element {
    const { problems, setResolvedProblem, getOnNext } = useContext(QAContext);
    const { onNext, onClose, activeStep } = useContext(WizardContext);
    const problem = problems[props.idx];
    const onChange = (value: string): void => {
        setResolvedProblem(props.idx, { ...problem, answer: value });
    };
    return (
        <div>
            <TextContent>{problem.description}</TextContent>
            <TextInput
                isDisabled={props.idx !== problems.length - 1}
                type="text"
                aria-label="answer input"
                value={problem.answer as string}
                onChange={onChange}
                onKeyUp={(e) => e.key === 'Enter' && getOnNext(onNext, onClose, activeStep)()}
            />
            {problem.hints?.length && <Hints hints={problem.hints} />}
        </div>
    );
}

export { Input };
